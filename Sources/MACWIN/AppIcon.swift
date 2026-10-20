import AppKit

/// 옛날 윈도우 로고 아이콘 (Icons8, https://icons8.com — 무료 라이선스라 정보 화면에 출처 표시)
enum AppIcon {
    static let creditURL = URL(string: "https://icons8.com")!

    /// 앱 번들 Resources의 로고. 번들 없이 실행하면(swift run) 기본 심볼로 대신함
    static func logo(size: CGFloat) -> NSImage {
        let image = (Bundle.main.image(forResource: "windows98-96")?.copy() as? NSImage)
            ?? NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "MACWIN")!
        image.size = NSSize(width: size, height: size)
        return image
    }

    static func showAbout() {
        let credits = NSMutableAttributedString(
            string: "맥 파일명을 윈도우·웹 업로드용으로 검토하고 고칩니다.\n\n아이콘: ",
            attributes: [.font: NSFont.systemFont(ofSize: 11)])
        credits.append(NSAttributedString(string: "Icons8", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .link: creditURL,
        ]))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
