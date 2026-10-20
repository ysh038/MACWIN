import Foundation

/// ZIP 안에서 이름이 문제 되는 항목
public struct ZipEntryIssue: Identifiable {
    public let id: Int
    /// 원래 이름 (화면 표시용으로 NFC)
    public let originalPath: String
    /// 윈도우용으로 고친 이름
    public let newPath: String
    public let isDirectory: Bool
    public let issues: [IssueKind]

    public var looksSame: Bool { originalPath == newPath }
}

public struct ZipInspection {
    public var path = ""
    public var entryCount = 0
    /// 뺄 맥 숨김파일 항목 수 (__MACOSX/, ._*, .DS_Store)
    public var junkCount = 0
    public var encrypted = false
    public var issues: [ZipEntryIssue] = []
    /// 고칠 수 없는 ZIP이면 이유
    public var unsupported: String?

    public var needsRepair: Bool { unsupported == nil && (!issues.isEmpty || junkCount > 0) }

    public init() {}
}

/// 이미 만든 ZIP의 이름표만 고쳐서 새 ZIP으로 저장. 내용은 압축된 그대로 옮겨 담아서 바뀌지 않습니다.
public enum ZipRepair {
    struct Entry {
        var madeBy: UInt16, flags: UInt16
        var crc: UInt32, csize: UInt32, usize: UInt32
        var method: UInt16, time: UInt16, date: UInt16
        var nameBytes: Data, extra: Data, comment: Data
        var internalAttr: UInt16, externalAttr: UInt32, localOffset: UInt32
    }

    struct Archive {
        var entries: [Entry]
        var comment: Data
    }

    struct Planned {
        let entry: Entry
        let original: String
        let newName: String
        let isDir: Bool
        let issues: [IssueKind]
        /// 같은 이름이 겹쳐서 " (2)" 등을 붙였는지
        let collided: Bool

        /// 이 항목 자신의 이름이 바뀌는지 (상위 폴더만 바뀐 경우는 제외)
        var changed: Bool { !issues.isEmpty || collided }
    }

    struct Unsupported: Error { let reason: String }

    public static func isZipFile(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return (path as NSString).pathExtension.lowercased() == "zip"
            && FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
    }

    /// "이름 (윈도우용).zip". 이미 있으면 "이름 (윈도우용) 2.zip"
    public static func defaultOutputPath(for path: String) -> String {
        let dir = (path as NSString).deletingLastPathComponent
        let stem = Rules.sanitize(((path as NSString).lastPathComponent as NSString).deletingPathExtension).fixed + " (윈도우용)"
        var candidate = dir + "/" + stem + ".zip"
        var n = 2
        while FileManager.default.fileExists(atPath: candidate) {
            candidate = dir + "/" + stem + " \(n).zip"
            n += 1
        }
        return candidate
    }

    public static func inspect(path: String) -> ZipInspection {
        var result = ZipInspection()
        result.path = path
        do {
            let input = try openRead(path)
            defer { try? input.close() }
            let archive = try readArchive(input)
            result.entryCount = archive.entries.count
            result.encrypted = archive.entries.contains { $0.flags & 1 != 0 }
            let (planned, junk) = plan(archive)
            result.junkCount = junk
            for (i, p) in planned.enumerated() where p.changed {
                result.issues.append(ZipEntryIssue(id: i, originalPath: p.original.precomposedStringWithCanonicalMapping,
                                                   newPath: p.newName, isDirectory: p.isDir, issues: p.issues))
            }
        } catch let u as Unsupported {
            result.unsupported = u.reason
        } catch {
            result.unsupported = error.localizedDescription
        }
        return result
    }

    public static func repair(path: String, to output: String, options: ZipOptions = ZipOptions(),
                              progress: ((Double) -> Void)? = nil) throws -> ZipReport {
        let input = try openRead(path)
        defer { try? input.close() }
        let archive: Archive
        do { archive = try readArchive(input) } catch let u as Unsupported { throw ZipError.io(u.reason) }
        let (planned, junk) = plan(archive)

        var report = ZipReport()
        report.output = output
        report.excludedJunk = junk

        let dir = (output as NSString).deletingLastPathComponent
        let tmp = dir + "/.macwin-" + UUID().uuidString + ".zip"
        let fd = tmp.withCString { open($0, O_WRONLY | O_CREAT | O_EXCL, 0o644) }
        guard fd >= 0 else { throw ZipError.io("ZIP 파일을 만들 수 없어요: " + String(cString: strerror(errno))) }
        let out = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var succeeded = false
        defer {
            try? out.close()
            if !succeeded { _ = tmp.withCString { unlink($0) } }
        }

        let total = planned.reduce(UInt64(0)) { $0 + UInt64($1.entry.csize) }
        var copied: UInt64 = 0
        var central = Data()

        for p in planned {
            let e = p.entry
            try input.seek(toOffset: UInt64(e.localOffset))
            guard let lh = try input.read(upToCount: 30), lh.count == 30, lh.u32(0) == 0x0403_4b50 else {
                throw ZipError.io("ZIP이 손상됐어요: \(p.original)")
            }
            let localNameLen = UInt64(lh.u16(26)), localExtraLen = Int(lh.u16(28))
            try input.seek(toOffset: UInt64(e.localOffset) + 30 + localNameLen)
            let localExtra = try input.read(upToCount: localExtraLen) ?? Data()
            let dataStart = UInt64(e.localOffset) + 30 + localNameLen + UInt64(localExtraLen)

            // 데이터 뒤에 붙는 기술자(bit 3)는 암호 확인에도 쓰이므로 그대로 옮김
            var dataLen = UInt64(e.csize)
            if e.flags & 0x0008 != 0 {
                try input.seek(toOffset: dataStart + dataLen)
                let sig = try input.read(upToCount: 4) ?? Data()
                dataLen += (sig.count == 4 && sig.u32(0) == 0x0807_4b50) ? 16 : 12
            }

            let (nameBytes, nameExtra, utf8Flag) = Zipper.encodeName(p.newName, legacy: options.legacyCP949)
            let flags = (e.flags & ~UInt16(0x0800)) | utf8Flag
            let newLocalExtra = stripUnicodePath(localExtra) + nameExtra
            let newCentralExtra = stripUnicodePath(e.extra) + nameExtra
            let offset = try out.offset()

            var local = Data()
            local.le32(0x0403_4b50)
            local.le16(lh.u16(4)); local.le16(flags); local.le16(lh.u16(8)); local.le16(lh.u16(10)); local.le16(lh.u16(12))
            local.le32(lh.u32(14)); local.le32(lh.u32(18)); local.le32(lh.u32(22))
            local.le16(UInt16(nameBytes.count)); local.le16(UInt16(newLocalExtra.count))
            local.append(nameBytes); local.append(newLocalExtra)
            try out.write(contentsOf: local)

            try input.seek(toOffset: dataStart)
            var remaining = dataLen
            while remaining > 0 {
                let n = Int(min(remaining, 1 << 20))
                guard let chunk = try input.read(upToCount: n), !chunk.isEmpty else {
                    throw ZipError.io("ZIP이 손상됐어요: \(p.original)")
                }
                try out.write(contentsOf: chunk)
                remaining -= UInt64(chunk.count)
                copied += UInt64(chunk.count)
                if total > 0 { progress?(min(1, Double(copied) / Double(total))) }
            }
            if try out.offset() >= 0xFFFF_FFFF { throw ZipError.tooLarge }

            central.le32(0x0201_4b50)
            central.le16(e.madeBy); central.le16(lh.u16(4)); central.le16(flags); central.le16(e.method)
            central.le16(e.time); central.le16(e.date)
            central.le32(e.crc); central.le32(e.csize); central.le32(e.usize)
            central.le16(UInt16(nameBytes.count)); central.le16(UInt16(newCentralExtra.count))
            central.le16(UInt16(e.comment.count))
            central.le16(0); central.le16(e.internalAttr); central.le32(e.externalAttr)
            central.le32(UInt32(offset))
            central.append(nameBytes); central.append(newCentralExtra); central.append(e.comment)

            if p.isDir { report.dirCount += 1 } else { report.fileCount += 1 }
            if p.changed { report.renamed += 1 }
        }

        let centralOffset = try out.offset()
        try out.write(contentsOf: central)
        var end = Data()
        end.le32(0x0605_4b50)
        end.le16(0); end.le16(0)
        end.le16(UInt16(planned.count)); end.le16(UInt16(planned.count))
        end.le32(UInt32(central.count)); end.le32(UInt32(centralOffset))
        end.le16(UInt16(archive.comment.count))
        end.append(archive.comment)
        try out.write(contentsOf: end)
        try out.synchronize()

        let rc = tmp.withCString { a in output.withCString { b in renamex_np(a, b, UInt32(RENAME_EXCL)) } }
        guard rc == 0 else { throw ZipError.io("ZIP 파일 이름을 정할 수 없어요: " + String(cString: strerror(errno))) }
        succeeded = true
        progress?(1)
        return report
    }

    // MARK: - 읽기

    static func openRead(_ path: String) throws -> FileHandle {
        let fd = path.withCString { open($0, O_RDONLY) }
        guard fd >= 0 else { throw ZipError.io("ZIP 파일을 열 수 없어요: " + String(cString: strerror(errno))) }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    static func readArchive(_ input: FileHandle) throws -> Archive {
        let size = try input.seekToEnd()
        let tailLen = min(size, 22 + 0xFFFF)
        try input.seek(toOffset: size - tailLen)
        let tail = try input.read(upToCount: Int(tailLen)) ?? Data()

        var eocd: Int?
        var i = tail.count - 22
        while i >= 0 {
            if tail.u32(i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard let e = eocd else { throw Unsupported(reason: "ZIP 파일이 아니거나 손상됐어요.") }

        let count = tail.u16(e + 10), cdSize = tail.u32(e + 12), cdOffset = tail.u32(e + 16)
        if tail.u16(e + 4) != 0 || tail.u16(e + 6) != 0 || tail.u16(e + 8) != count {
            throw Unsupported(reason: "분할 압축(.z01 등)은 아직 고칠 수 없어요.")
        }
        if count == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF
            || (e >= 20 && tail.u32(e - 20) == 0x0706_4b50) {
            throw Unsupported(reason: "4GB가 넘는 큰 ZIP(ZIP64)은 아직 고칠 수 없어요.")
        }
        let commentLen = Int(tail.u16(e + 20))
        let comment = tail.subdata(in: (e + 22)..<min(tail.count, e + 22 + commentLen))

        try input.seek(toOffset: UInt64(cdOffset))
        let cd = try input.read(upToCount: Int(cdSize)) ?? Data()
        guard cd.count == Int(cdSize) else { throw Unsupported(reason: "ZIP이 손상됐어요.") }

        var entries: [Entry] = []
        var p = 0
        for _ in 0..<count {
            guard p + 46 <= cd.count, cd.u32(p) == 0x0201_4b50 else { throw Unsupported(reason: "ZIP이 손상됐어요.") }
            let n = Int(cd.u16(p + 28)), m = Int(cd.u16(p + 30)), k = Int(cd.u16(p + 32))
            guard p + 46 + n + m + k <= cd.count else { throw Unsupported(reason: "ZIP이 손상됐어요.") }
            let extra = cd.subdata(in: (p + 46 + n)..<(p + 46 + n + m))
            if extraField(extra, id: 0x0001) != nil { throw Unsupported(reason: "4GB가 넘는 큰 ZIP(ZIP64)은 아직 고칠 수 없어요.") }
            entries.append(Entry(
                madeBy: cd.u16(p + 4), flags: cd.u16(p + 8),
                crc: cd.u32(p + 16), csize: cd.u32(p + 20), usize: cd.u32(p + 24),
                method: cd.u16(p + 10), time: cd.u16(p + 12), date: cd.u16(p + 14),
                nameBytes: cd.subdata(in: (p + 46)..<(p + 46 + n)), extra: extra,
                comment: cd.subdata(in: (p + 46 + n + m)..<(p + 46 + n + m + k)),
                internalAttr: cd.u16(p + 36), externalAttr: cd.u32(p + 38), localOffset: cd.u32(p + 42)))
            p += 46 + n + m + k
        }
        return Archive(entries: entries, comment: comment)
    }

    /// (이름, UTF-8인데 표시가 없는지)
    static func decodeName(_ e: Entry) -> (String, Bool) {
        if e.flags & 0x0800 != 0 { return (String(decoding: e.nameBytes, as: UTF8.self), false) }
        if let field = extraField(e.extra, id: 0x7075), field.count > 5, field[field.startIndex] == 1,
           field.u32(1) == CRC32.update(0, e.nameBytes),
           let name = String(data: field.subdata(in: (field.startIndex + 5)..<field.endIndex), encoding: .utf8) {
            return (name, false)
        }
        if e.nameBytes.allSatisfy({ $0 < 0x80 }) { return (String(decoding: e.nameBytes, as: UTF8.self), false) }
        if let name = String(data: e.nameBytes, encoding: .utf8) { return (name, true) }
        if let name = String(data: e.nameBytes, encoding: Zipper.cp949) { return (name, false) }
        return (String(decoding: e.nameBytes, as: UTF8.self), false)
    }

    // MARK: - 새 이름 정하기

    /// 같은 원래 폴더는 항상 같은 새 폴더 이름이 되도록 기억하면서 이름을 고침
    static func plan(_ archive: Archive) -> ([Planned], Int) {
        var planned: [Planned] = []
        var junk = 0
        var dirMap: [String: String] = [:]        // 원래 폴더 경로 → 새 폴더 경로
        var used: [String: Set<String>] = [:]     // 새 폴더 경로 → 안에 있는 이름들(윈도우 기준)
        var fileMap: [String: String] = [:]

        func child(_ name: String, in parent: String) -> String {
            var set = used[parent] ?? []
            var dummy = ZipReport()
            let fixed = Zipper.uniqueName(for: name, in: &set, report: &dummy)
            used[parent] = set
            return fixed
        }

        for e in archive.entries {
            let (name, noFlag) = decodeName(e)
            let isDir = name.hasSuffix("/")
            let comps = name.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            if comps.isEmpty || comps.contains(where: Rules.isMacJunk) { junk += 1; continue }

            var issues: [IssueKind] = []
            var collided = false
            func note(_ comp: String, _ fixed: String) {
                if !Rules.sameScalars(fixed, Rules.sanitize(comp).fixed) { collided = true }
                for k in Rules.sanitize(comp).issues where !issues.contains(k) { issues.append(k) }
                if noFlag, comp.unicodeScalars.contains(where: { !$0.isASCII }), !issues.contains(.zipNoUTF8Flag) {
                    issues.append(.zipNoUTF8Flag)
                }
            }

            var origParent = "", newParent = ""
            var newName = ""
            for (i, c) in comps.enumerated() {
                let isLast = i == comps.count - 1
                if !isLast || isDir {
                    let key = origParent + c + "/"
                    if let mapped = dirMap[key] {
                        newParent = mapped
                    } else {
                        let fixed = child(c, in: newParent)
                        note(c, fixed)
                        newParent = newParent + fixed + "/"
                        dirMap[key] = newParent
                    }
                    origParent = key
                    newName = newParent
                } else {
                    let key = origParent + c
                    if let mapped = fileMap[key] {
                        newName = mapped   // 같은 이름이 두 번 들어있는 ZIP
                    } else {
                        let fixed = child(c, in: newParent)
                        note(c, fixed)
                        newName = newParent + fixed
                        fileMap[key] = newName
                    }
                }
            }
            planned.append(Planned(entry: e, original: name, newName: newName, isDir: isDir, issues: issues, collided: collided))
        }
        return (planned, junk)
    }

    // MARK: - 확장 필드

    static func extraField(_ extra: Data, id: UInt16) -> Data? {
        var p = 0
        while p + 4 <= extra.count {
            let fid = extra.u16(p), len = Int(extra.u16(p + 2))
            guard p + 4 + len <= extra.count else { return nil }
            if fid == id { return extra.subdata(in: (extra.startIndex + p + 4)..<(extra.startIndex + p + 4 + len)) }
            p += 4 + len
        }
        return nil
    }

    /// 예전 이름용 UTF-8 필드(0x7075)는 새 이름과 안 맞으므로 지움
    static func stripUnicodePath(_ extra: Data) -> Data {
        var out = Data()
        var p = 0
        while p + 4 <= extra.count {
            let fid = extra.u16(p), len = Int(extra.u16(p + 2))
            guard p + 4 + len <= extra.count else { break }
            if fid != 0x7075 { out.append(extra.subdata(in: (extra.startIndex + p)..<(extra.startIndex + p + 4 + len))) }
            p += 4 + len
        }
        return out
    }
}

extension Data {
    func u16(_ i: Int) -> UInt16 {
        UInt16(self[startIndex + i]) | UInt16(self[startIndex + i + 1]) << 8
    }

    func u32(_ i: Int) -> UInt32 {
        UInt32(u16(i)) | UInt32(u16(i + 2)) << 16
    }
}
