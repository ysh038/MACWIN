import Foundation

public struct RenameRecord: Codable {
    /// 이름을 바꿀 당시의 부모 폴더 경로
    public let parent: String
    public let old: String
    public let new: String

    public init(parent: String, old: String, new: String) {
        self.parent = parent
        self.old = old
        self.new = new
    }
}

public struct ApplyReport {
    public var done: [RenameRecord] = []
    public var failed: [(path: String, reason: String)] = []
    public init() {}
}

public enum Fixer {
    /// 깊은 것부터 바꿔서 부모 경로가 중간에 바뀌지 않게 함
    public static func apply(_ findings: [Finding]) -> ApplyReport {
        var report = ApplyReport()
        let ordered = findings.filter(\.isFixable).sorted { $0.depth > $1.depth }
        for f in ordered {
            guard let newName = f.newName else { continue }
            do {
                try rename(in: f.parentPath, from: f.name, to: newName)
                report.done.append(RenameRecord(parent: f.parentPath, old: f.name, new: newName))
            } catch {
                report.failed.append((f.displayPath, error.localizedDescription))
            }
        }
        if !report.done.isEmpty { History.save(report.done) }
        return report
    }

    /// 마지막 작업을 거꾸로 되돌림
    public static func undo(_ records: [RenameRecord]) -> ApplyReport {
        var report = ApplyReport()
        for r in records.reversed() {
            do {
                try rename(in: r.parent, from: r.new, to: r.old)
                report.done.append(RenameRecord(parent: r.parent, old: r.new, new: r.old))
            } catch {
                report.failed.append((r.parent + "/" + r.new, error.localizedDescription))
            }
        }
        return report
    }

    /// 덮어쓰기 없이 이름 바꾸기. NFD→NFC, 대소문자만 다른 경우처럼 파일시스템이 같은 이름으로
    /// 보는 경우에는 임시 이름을 거쳐서 바꿈.
    static func rename(in dir: String, from: String, to: String) throws {
        let src = dir + "/" + from
        let dst = dir + "/" + to
        if Rules.windowsKey(from) == Rules.windowsKey(to) {
            let tmp = dir + "/.macwin-" + UUID().uuidString
            try renameExcl(src, tmp)
            do {
                try renameExcl(tmp, dst)
            } catch {
                try? renameExcl(tmp, src)
                throw error
            }
        } else {
            try renameExcl(src, dst)
        }
    }

    static func renameExcl(_ a: String, _ b: String) throws {
        let rc = a.withCString { pa in b.withCString { pb in renamex_np(pa, pb, UInt32(RENAME_EXCL)) } }
        if rc != 0 {
            let code = errno
            let msg = code == EEXIST ? tr("A file with that name already exists") : String(cString: strerror(code))
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
}

/// 마지막 수정 기록 (되돌리기용)
public enum History {
    static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MACWIN", isDirectory: true)
    }
    static var lastFile: URL { dir.appendingPathComponent("last.json") }
    static var logFile: URL { dir.appendingPathComponent("history.log") }

    public static var hasLast: Bool { FileManager.default.fileExists(atPath: lastFile.path) }

    static func save(_ records: [RenameRecord]) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(records) { try? data.write(to: lastFile) }

        let stamp = ISO8601DateFormatter().string(from: Date())
        var log = ""
        for r in records { log += "\(stamp)\t\(r.parent)/\(r.old)\t→\t\(r.new)\n" }
        if let h = try? FileHandle(forWritingTo: logFile) {
            h.seekToEndOfFile(); h.write(Data(log.utf8)); try? h.close()
        } else {
            try? Data(log.utf8).write(to: logFile)
        }
    }

    public static func loadLast() -> [RenameRecord]? {
        guard let data = try? Data(contentsOf: lastFile) else { return nil }
        return try? JSONDecoder().decode([RenameRecord].self, from: data)
    }

    public static func clearLast() {
        try? FileManager.default.removeItem(at: lastFile)
    }
}
