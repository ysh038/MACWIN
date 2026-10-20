import AppKit
import ScrubCore

final class ScrubModel: ObservableObject {
    enum Phase { case idle, scanning, scanned, done }

    @Published var phase: Phase = .idle
    @Published var result = ScanResult()
    @Published var selected = Set<Int>()
    @Published var report = ApplyReport()
    @Published var canUndo = History.hasLast
    @Published var notice: String?

    var showPopover: (() -> Void)?
    var hidePopover: (() -> Void)?
    private var lastURLs: [URL] = []

    func scan(_ urls: [URL]) {
        lastURLs = urls
        notice = nil
        phase = .scanning
        let paths = urls.map(\.path)
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Scanner.scan(paths: paths)
            DispatchQueue.main.async {
                self.result = r
                self.selected = Set(r.fixable.map(\.id))
                self.phase = .scanned
            }
        }
    }

    func rescan() { scan(lastURLs) }

    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "검사"
        hidePopover?()
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            scan(panel.urls)
        }
        showPopover?()
    }

    func scrub() {
        let picked = result.findings.filter { selected.contains($0.id) }
        report = Fixer.apply(picked)
        canUndo = History.hasLast
        phase = .done
    }

    func undo() {
        guard let last = History.loadLast() else { canUndo = false; return }
        let rep = Fixer.undo(last)
        if rep.failed.isEmpty {
            History.clearLast()
            notice = "\(rep.done.count)개를 원래 이름으로 되돌렸어요."
        } else {
            notice = "\(rep.done.count)개 되돌림, \(rep.failed.count)개 실패: " + rep.failed.map(\.path).joined(separator: ", ")
        }
        canUndo = History.hasLast
        phase = .idle
    }

    func reset() {
        notice = nil
        phase = .idle
    }

    func toggleAll() {
        let all = Set(result.fixable.map(\.id))
        selected = selected == all ? [] : all
    }
}
