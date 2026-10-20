import Foundation

/// 윈도우로 옮길 때 문제가 되는 파일명 유형.
public enum IssueKind: String, Codable, CaseIterable {
    // 자동으로 고칠 수 있는 것
    case nfd
    case invisibleChar
    case controlChar
    case forbiddenChar
    case trailingDotSpace
    case reservedName
    case zipNoUTF8Flag
    // 경고만 (자동으로 안 고침)
    case nameConflict
    case caseCollision
    case longPath

    public var isFixable: Bool {
        switch self {
        case .nfd, .invisibleChar, .controlChar, .forbiddenChar, .trailingDotSpace, .reservedName, .zipNoUTF8Flag:
            return true
        case .nameConflict, .caseCollision, .longPath: return false
        }
    }

    public var title: String {
        switch self {
        case .nfd: return tr("Decomposed (NFD)")
        case .invisibleChar: return tr("Special space")
        case .controlChar: return tr("Control character")
        case .forbiddenChar: return tr("Forbidden character")
        case .trailingDotSpace: return tr("Trailing space/dot")
        case .reservedName: return tr("Reserved name")
        case .zipNoUTF8Flag: return tr("No UTF-8 flag")
        case .nameConflict: return tr("Name conflict")
        case .caseCollision: return tr("Case conflict")
        case .longPath: return tr("Long path")
        }
    }

    public var detail: String {
        switch self {
        case .nfd: return tr("Converts Mac-style (NFD) characters to Windows-style (NFC). The name looks the same.")
        case .invisibleChar: return tr("Replaces narrow and zero-width spaces with normal spaces, or removes them.")
        case .controlChar: return tr("Replaces invisible control characters with _.")
        case .forbiddenChar: return tr("Replaces \\ : * ? \" < > |, which Windows doesn't allow, with _.")
        case .trailingDotSpace: return tr("Windows strips spaces and dots at the end of names, so they are removed in advance.")
        case .reservedName: return tr("Names like CON, NUL and COM1 can't be created on Windows, so _ is appended.")
        case .zipNoUTF8Flag: return tr("The ZIP doesn't mark its names as UTF-8, so Windows misreads them as CP949 and garbles them. The flag is added.")
        case .nameConflict: return tr("The fixed name would clash with another file in the same folder, so it is skipped. Please rename it yourself.")
        case .caseCollision: return tr("Another name differs only in case. On Windows, one will overwrite the other.")
        case .longPath: return tr("The path is long and may hit the Windows 260-character limit.")
        }
    }
}

public enum Rules {
    static let forbidden: Set<UInt32> = Set("\\:*?\"<>|".unicodeScalars.map(\.value))
    /// 일반 공백으로 바꿀 공백류
    static let spaceLike: Set<UInt32> = [0x00A0, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006,
                                         0x2007, 0x2008, 0x2009, 0x200A, 0x202F, 0x205F]
    /// 지울 제로폭 문자
    static let zeroWidth: Set<UInt32> = [0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF]
    static let reserved: Set<String> = {
        var s: Set<String> = ["CON", "PRN", "AUX", "NUL"]
        for i in 0...9 { s.insert("COM\(i)"); s.insert("LPT\(i)") }
        return s
    }()

    /// 맥이 만드는 숨김/메타 파일. 건드리지 않고 개수만 셉니다.
    static let macJunkNames: Set<String> = [".DS_Store", "__MACOSX", ".Spotlight-V100", ".Trashes", ".fseventsd",
                                            ".TemporaryItems", ".DocumentRevisions-V100", ".VolumeIcon.icns",
                                            ".localized", "Icon\r"]
    /// 안쪽은 건드리면 안 되는 폴더
    static let noDescend: Set<String> = [".git", ".svn", ".hg"]

    public static func isMacJunk(_ name: String) -> Bool {
        macJunkNames.contains(name) || name.hasPrefix("._")
    }

    /// 이름을 윈도우에서 안전한 이름으로 바꾼 결과와 발견된 문제들.
    /// 주의: Swift의 String ==는 NFD/NFC를 같다고 보므로 비교는 항상 unicodeScalars로 합니다.
    public static func sanitize(_ name: String) -> (fixed: String, issues: [IssueKind]) {
        var issues: [IssueKind] = []
        let nfc = name.precomposedStringWithCanonicalMapping
        if !sameScalars(nfc, name) { issues.append(.nfd) }

        var scalars = String.UnicodeScalarView()
        var invisible = false, control = false, forbiddenHit = false
        for s in nfc.unicodeScalars {
            if spaceLike.contains(s.value) {
                scalars.append(" "); invisible = true
            } else if zeroWidth.contains(s.value) {
                invisible = true
            } else if s.value < 0x20 || s.value == 0x7F {
                scalars.append("_"); control = true
            } else if forbidden.contains(s.value) {
                scalars.append("_"); forbiddenHit = true
            } else {
                scalars.append(s)
            }
        }
        if invisible { issues.append(.invisibleChar) }
        if control { issues.append(.controlChar) }
        if forbiddenHit { issues.append(.forbiddenChar) }

        var out = String(scalars)
        if out != "." && out != ".." {
            var trimmed = out
            while let last = trimmed.unicodeScalars.last, last == "." || last == " " {
                trimmed.unicodeScalars.removeLast()
            }
            if trimmed.unicodeScalars.count != out.unicodeScalars.count {
                issues.append(.trailingDotSpace)
                out = trimmed.isEmpty ? "_" : trimmed
            }
        }

        // CON, con.txt, COM1.tar.gz 모두 예약어
        let dot = out.firstIndex(of: ".") ?? out.endIndex
        let base = String(out[..<dot])
        var baseKey = base
        while baseKey.hasSuffix(" ") { baseKey.removeLast() }
        if reserved.contains(baseKey.uppercased()) {
            out = base + "_" + String(out[dot...])
            issues.append(.reservedName)
        }
        return (out, issues)
    }

    public static func sameScalars(_ a: String, _ b: String) -> Bool {
        a.unicodeScalars.elementsEqual(b.unicodeScalars)
    }

    /// 윈도우 기준으로 같은 이름인지 판단하는 키 (대소문자 무시)
    static func windowsKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    static func windowsKeyTaken(_ name: String, in used: Set<String>) -> Bool {
        used.contains(windowsKey(name))
    }
}
