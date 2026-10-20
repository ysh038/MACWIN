import Foundation

/// 화면 문구. 키는 영어 원문이고, 시스템 언어가 한국어면 앱 번들의 ko.lproj/Localizable.strings에서 찾습니다.
/// 앱 번들 밖(macwin-cli 등)에서는 영어 그대로 나옵니다.
public func tr(_ key: String, _ args: CVarArg...) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
    return args.isEmpty ? format : String(format: format, arguments: args)
}
