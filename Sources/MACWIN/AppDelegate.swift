import AppKit
import SwiftUI

/// 테두리 없는 패널도 키 입력(엔터 등)을 받을 수 있게
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 메뉴바 아이콘. 클릭하면 아래에 창이 열리고, 아이콘 위에 파일/폴더를 놓으면 바로 검사합니다.
/// NSPopover는 위치를 macOS가 정해서 메뉴바에 딱 붙으므로 직접 위치를 잡는 패널을 씁니다.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSDraggingDestination {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private let model = ScrubModel()
    private var clickMonitor: Any?
    private var keyMonitor: Any?

    private let panelSize = NSSize(width: 420, height: 500)
    /// 메뉴바와 창 사이 간격
    private let gap: CGFloat = 8

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "MACWIN")
            button.target = self
            button.action = #selector(togglePanel)
            // 상태바 버튼의 창에 드롭을 등록하면 창 delegate로 드래그 메시지가 옴
            button.window?.registerForDraggedTypes([.fileURL])
            button.window?.delegate = self
        }
        panel = makePanel()
        model.showPopover = { [weak self] in self?.showPanel() }
        model.hidePopover = { [weak self] in self?.hidePanel() }
    }

    private func makePanel() -> FloatingPanel {
        let p = FloatingPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let radius: CGFloat = 12
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        let mask = NSImage(size: NSSize(width: radius * 2 + 1, height: radius * 2 + 1), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        effect.maskImage = mask

        let hosting = NSHostingView(rootView: ContentView(model: model))
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)
        p.contentView = effect
        return p
    }

    @objc private func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }

    private func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero

        var x = buttonFrame.midX - panelSize.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - panelSize.width - 8)
        let y = min(buttonFrame.minY, visible.maxY) - gap - panelSize.height
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        statusItem.button?.highlight(true)

        // 바깥을 클릭하면 닫기. 단, 파일을 끌어오는 중(누른 채 움직임)이면 열어둬서 창에 놓을 수 있게 함
        if clickMonitor == nil {
            var closeOnRelease = false
            clickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]
            ) { [weak self] event in
                switch event.type {
                case .leftMouseDown: closeOnRelease = true
                case .leftMouseDragged: closeOnRelease = false
                case .leftMouseUp: if closeOnRelease { self?.hidePanel() }
                default: self?.hidePanel()
                }
            }
        }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { self?.hidePanel(); return nil }
                return event
            }
        }
    }

    private func hidePanel() {
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    // MARK: - 메뉴바 아이콘에 드롭

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        statusItem.button?.highlight(true)
        return .generic
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        if !panel.isVisible { statusItem.button?.highlight(false) }
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        model.scan(urls)
        showPanel()
        return true
    }
}
