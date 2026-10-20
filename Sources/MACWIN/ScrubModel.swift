import AppKit
import ScrubCore

final class ScrubModel: ObservableObject {
    enum Phase { case idle, scanning, scanned, done, zipInspected, zipping, zipped }

    @Published var phase: Phase = .idle
    @Published var result = ScanResult()
    @Published var selected = Set<Int>()
    @Published var report = ApplyReport()
    @Published var canUndo = History.hasLast
    @Published var notice: String?
    @Published var zipProgress = 0.0
    @Published var zipReport = ZipReport()
    @Published var zipError: String?
    /// ZIP 파일 하나를 올렸을 때 ZIP 안 이름 검사 결과
    @Published var zipInspection = ZipInspection()
    /// 옛날 윈도우·그룹웨어 호환 ZIP (CP949)
    @Published var legacyCP949 = UserDefaults.standard.bool(forKey: "zipLegacyCP949") {
        didSet { UserDefaults.standard.set(legacyCP949, forKey: "zipLegacyCP949") }
    }

    var showPopover: (() -> Void)?
    var hidePopover: (() -> Void)?
    private var lastURLs: [URL] = []

    func scan(_ urls: [URL]) {
        lastURLs = urls
        notice = nil
        phase = .scanning
        let paths = urls.map(\.path)
        // ZIP 파일 하나면 ZIP 안의 이름을 검사
        if paths.count == 1, ZipRepair.isZipFile(paths[0]) {
            DispatchQueue.global(qos: .userInitiated).async {
                let ins = ZipRepair.inspect(path: paths[0])
                DispatchQueue.main.async {
                    self.zipInspection = ins
                    self.phase = .zipInspected
                }
            }
            return
        }
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
        panel.prompt = tr("Check")
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
        // 맨 위 항목 이름이 바뀌었으면 다시 검사·ZIP 때 새 경로를 쓰도록
        lastURLs = lastURLs.map { url in
            let parent = (url.deletingLastPathComponent().path as NSString).standardizingPath
            let name = url.lastPathComponent
            guard let r = report.done.first(where: { ($0.parent as NSString).standardizingPath == parent && $0.old == name })
            else { return url }
            return URL(fileURLWithPath: r.parent).appendingPathComponent(r.new)
        }
        phase = .done
    }

    func undo() {
        guard let last = History.loadLast() else { canUndo = false; return }
        let rep = Fixer.undo(last)
        if rep.failed.isEmpty {
            History.clearLast()
            notice = tr("Restored %ld items to their original names.", rep.done.count)
        } else {
            notice = tr("Restored %ld, failed %ld: %@", rep.done.count, rep.failed.count, rep.failed.map(\.path).joined(separator: ", "))
        }
        canUndo = History.hasLast
        phase = .idle
    }

    /// 원본은 그대로 두고 윈도우용 ZIP을 원본 옆에 새로 압축
    func makeZip() {
        let paths = lastURLs.map(\.path)
        guard !paths.isEmpty else { return }
        let output = Zipper.defaultOutputPath(for: paths)
        runZipJob { options, progress in
            try Zipper.makeZip(paths: paths, to: output, options: options, progress: progress)
        }
    }

    /// 올린 ZIP은 그대로 두고 이름만 고친 "(윈도우용)" ZIP을 옆에 만듦
    func repairZip() {
        let path = zipInspection.path
        let output = ZipRepair.defaultOutputPath(for: path)
        runZipJob { options, progress in
            try ZipRepair.repair(path: path, to: output, options: options, progress: progress)
        }
    }

    private func runZipJob(_ job: @escaping (ZipOptions, @escaping (Double) -> Void) throws -> ZipReport) {
        let options = ZipOptions(legacyCP949: legacyCP949)
        zipProgress = 0
        zipError = nil
        phase = .zipping
        DispatchQueue.global(qos: .userInitiated).async {
            var lastSent = 0.0
            do {
                let rep = try job(options) { p in
                    guard p - lastSent >= 0.01 || p >= 1 else { return }
                    lastSent = p
                    DispatchQueue.main.async { self.zipProgress = p }
                }
                DispatchQueue.main.async { self.zipReport = rep; self.phase = .zipped }
            } catch {
                DispatchQueue.main.async { self.zipError = error.localizedDescription; self.phase = .zipped }
            }
        }
    }

    func revealZip() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: zipReport.output)])
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
