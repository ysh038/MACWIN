import Foundation

public struct Finding: Identifiable {
    public let id: Int
    /// 검사 당시 부모 폴더 경로 (원래 이름 그대로)
    public let parentPath: String
    /// 디스크에 저장된 원래 이름 (NFD일 수 있음)
    public let name: String
    /// 화면 표시용 상대 경로 (고친 이름 기준)
    public let displayPath: String
    public let isDirectory: Bool
    public let depth: Int
    public var issues: [IssueKind]
    /// 바꿀 이름. nil이면 이름을 바꾸지 않음 (경고만 있거나 충돌)
    public var newName: String?

    public var isFixable: Bool { newName != nil }
    /// NFD만 바뀌는 경우처럼 눈으로 보이는 이름이 같은지
    public var looksSame: Bool { newName.map { $0 == name } ?? true }
}

public struct ScanResult {
    public var roots: [String] = []
    public var findings: [Finding] = []
    public var scanned = 0
    public var junkCount = 0
    /// 안쪽을 검사하지 않은 폴더 (.git, 앱 번들 등)
    public var skipped: [String] = []

    public init() {}

    public var fixable: [Finding] { findings.filter(\.isFixable) }
    public var warnings: [Finding] { findings.filter { !$0.isFixable } }
}

public enum Scanner {
    /// 윈도우 쪽 경로(C:\Users\이름\Desktop\ 등)를 감안한 상대 경로 경고 기준
    public static var longPathLimit = 200

    struct Entry {
        let name: String
        let isDir: Bool
        let isLink: Bool
    }

    public static func scan(paths: [String]) -> ScanResult {
        var result = ScanResult()
        var nextID = 0

        let roots = dedupeRoots(paths.map { ($0 as NSString).standardizingPath })
        for rootPath in roots {
            let parent = (rootPath as NSString).deletingLastPathComponent
            let given = (rootPath as NSString).lastPathComponent
            // 드래그로 받은 경로는 NFC로 바뀌어 있을 수 있어서 실제 저장된 이름을 찾음
            let siblings = listDir(parent) ?? []
            guard let entry = siblings.first(where: { $0.name == given }) else { continue }
            result.roots.append(given.precomposedStringWithCanonicalMapping)

            let others = siblings.filter { !Rules.sameScalars($0.name, entry.name) }.map { Rules.windowsKey($0.name) }
            var conflict = false
            let fixedRoot = Rules.sanitize(entry.name).fixed
            if !Rules.sameScalars(fixedRoot, entry.name), others.contains(Rules.windowsKey(fixedRoot)) {
                conflict = true
            }
            visit(parent: parent, entry: entry, depth: 0, displayPrefix: "", conflict: conflict, caseDup: false,
                  parentTooLong: false, result: &result, nextID: &nextID)
        }
        return result
    }

    private static func visit(parent: String, entry: Entry, depth: Int, displayPrefix: String,
                              conflict: Bool, caseDup: Bool, parentTooLong: Bool,
                              result: inout ScanResult, nextID: inout Int) {
        result.scanned += 1
        if Rules.isMacJunk(entry.name) {
            result.junkCount += 1
            return
        }

        let path = parent + "/" + entry.name
        let (fixed, nameIssues) = Rules.sanitize(entry.name)
        var issues = nameIssues
        let renamed = !Rules.sameScalars(fixed, entry.name)
        let finalName = (renamed && !conflict) ? fixed : entry.name
        let display = displayPrefix.isEmpty ? finalName.precomposedStringWithCanonicalMapping
                                            : displayPrefix + "/" + finalName.precomposedStringWithCanonicalMapping

        if renamed && conflict { issues.append(.nameConflict) }
        if caseDup { issues.append(.caseCollision) }
        let tooLong = display.utf16.count > longPathLimit
        if tooLong && !parentTooLong { issues.append(.longPath) }

        if !issues.isEmpty {
            result.findings.append(Finding(id: nextID, parentPath: parent, name: entry.name, displayPath: display,
                                           isDirectory: entry.isDir, depth: depth, issues: issues,
                                           newName: (renamed && !conflict) ? fixed : nil))
            nextID += 1
        }

        guard entry.isDir, !entry.isLink else { return }
        if Rules.noDescend.contains(entry.name) || isPackage(path) {
            result.skipped.append(display)
            return
        }
        guard let children = listDir(path) else { return }

        // 같은 폴더 안에서 윈도우 기준으로 이름이 겹치는지 확인
        let live = children.filter { !Rules.isMacJunk($0.name) }
        let finals = live.map { c -> (key: String, renamed: Bool) in
            let f = Rules.sanitize(c.name).fixed
            return (Rules.windowsKey(f), !Rules.sameScalars(f, c.name))
        }
        var groups: [String: [Int]] = [:]
        for (i, f) in finals.enumerated() { groups[f.key, default: []].append(i) }

        var childConflict = Set<Int>(), childCaseDup = Set<Int>()
        for idxs in groups.values where idxs.count > 1 {
            for i in idxs {
                if finals[i].renamed { childConflict.insert(i) } else { childCaseDup.insert(i) }
            }
        }
        // 이름이 바뀌지 않는 쪽이 있으면 그게 우선, 바뀌는 쪽은 충돌로 건너뜀.
        // 이름이 바뀌지 않는 것끼리만 겹치면 대소문자 충돌.
        for idxs in groups.values where idxs.count > 1 {
            let unchanged = idxs.filter { !finals[$0].renamed }
            if unchanged.count < 2 { unchanged.forEach { childCaseDup.remove($0) } }
        }

        for (i, child) in live.enumerated() {
            visit(parent: path, entry: child, depth: depth + 1, displayPrefix: display,
                  conflict: childConflict.contains(i), caseDup: childCaseDup.contains(i),
                  parentTooLong: tooLong, result: &result, nextID: &nextID)
        }
        result.junkCount += children.count - live.count
        result.scanned += children.count - live.count
    }

    /// readdir로 디스크에 저장된 바이트 그대로의 이름을 읽음 (Foundation을 거치면 정규화될 수 있음)
    static func listDir(_ path: String) -> [Entry]? {
        guard let dir = opendir(path) else { return nil }
        defer { closedir(dir) }
        var out: [Entry] = []
        while let ent = readdir(dir) {
            let len = Int(ent.pointee.d_namlen)
            let name = withUnsafeBytes(of: &ent.pointee.d_name) { raw in
                String(decoding: raw.prefix(len), as: UTF8.self)
            }
            if name == "." || name == ".." { continue }
            var type = Int32(ent.pointee.d_type)
            if type == DT_UNKNOWN {
                var st = stat()
                if lstat(path + "/" + name, &st) == 0 {
                    switch st.st_mode & S_IFMT {
                    case S_IFDIR: type = DT_DIR
                    case S_IFLNK: type = DT_LNK
                    default: type = DT_REG
                    }
                }
            }
            out.append(Entry(name: name, isDir: type == DT_DIR, isLink: type == DT_LNK))
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func isPackage(_ path: String) -> Bool {
        (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
    }

    /// 다른 루트 안에 들어있는 루트는 빼기
    static func dedupeRoots(_ paths: [String]) -> [String] {
        let unique = Array(Set(paths)).sorted()
        return unique.filter { p in !unique.contains { other in other != p && p.hasPrefix(other + "/") } }
    }
}
