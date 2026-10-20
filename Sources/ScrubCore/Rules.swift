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
    // 경고만 (자동으로 안 고침)
    case nameConflict
    case caseCollision
    case longPath

    public var isFixable: Bool {
        switch self {
        case .nfd, .invisibleChar, .controlChar, .forbiddenChar, .trailingDotSpace, .reservedName: return true
        case .nameConflict, .caseCollision, .longPath: return false
        }
    }

    public var title: String {
        switch self {
        case .nfd: return "자소분리"
        case .invisibleChar: return "특수 공백"
        case .controlChar: return "제어 문자"
        case .forbiddenChar: return "금지 문자"
        case .trailingDotSpace: return "끝 공백/점"
        case .reservedName: return "예약어"
        case .nameConflict: return "이름 충돌"
        case .caseCollision: return "대소문자 충돌"
        case .longPath: return "긴 경로"
        }
    }

    public var detail: String {
        switch self {
        case .nfd: return "맥식(NFD) 한글 → 윈도우식(NFC)으로 바꿉니다. 보이는 이름은 그대로예요."
        case .invisibleChar: return "좁은 공백·제로폭 문자 등을 일반 공백으로 바꾸거나 지웁니다."
        case .controlChar: return "보이지 않는 제어 문자를 _ 로 바꿉니다."
        case .forbiddenChar: return "윈도우에서 못 쓰는 \\ : * ? \" < > | 를 _ 로 바꿉니다."
        case .trailingDotSpace: return "윈도우는 이름 끝의 공백·마침표를 지워버려서 미리 지웁니다."
        case .reservedName: return "CON, NUL, COM1 같은 이름은 윈도우에서 못 만들어서 뒤에 _ 를 붙입니다."
        case .nameConflict: return "고친 이름이 같은 폴더의 다른 파일과 겹쳐서 건너뜁니다. 직접 바꿔주세요."
        case .caseCollision: return "대소문자만 다른 이름이 있어요. 윈도우에선 하나가 덮어써집니다."
        case .longPath: return "경로가 길어서 윈도우 260자 제한에 걸릴 수 있어요."
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
}
