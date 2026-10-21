import AppKit
import ScrubCore

/// README 캡처용: MACWIN --demo <화면> <샘플 폴더> <샘플 ZIP> [--dark]
/// 화면: idle | scanned | done | zip | zipped
/// 앱이 그 화면 상태로 창을 띄우고, 창 번호와 캡처 영역(screencapture -R용)을 stdout에 적습니다.
/// 샘플 폴더의 파일 이름은 바꾸지 않습니다.
struct Demo {
    let state: String
    let sampleDir: String
    let zipPath: String
    let dark: Bool

    static let current: Demo? = {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--demo"), i + 3 < a.count else { return nil }
        return Demo(state: a[i + 1], sampleDir: a[i + 2], zipPath: a[i + 3], dark: a.contains("--dark"))
    }()

    func apply(to model: ScrubModel) {
        switch state {
        case "scanned", "done", "zipped":
            let result = Scanner.scan(paths: [sampleDir])
            model.result = result
            model.selected = Set(result.fixable.map(\.id))
            model.phase = .scanned
            if state == "done" {
                var report = ApplyReport()
                report.done = result.fixable.compactMap { f in
                    f.newName.map { RenameRecord(parent: f.parentPath, old: f.name, new: $0) }
                }
                model.report = report
                model.canUndo = true
                model.phase = .done
            } else if state == "zipped" {
                let out = Zipper.defaultOutputPath(for: [sampleDir])
                if let rep = try? Zipper.makeZip(paths: [sampleDir], to: out) {
                    try? FileManager.default.removeItem(atPath: out)
                    model.zipReport = rep
                    model.phase = .zipped
                }
            }
        case "zip":
            model.zipInspection = ZipRepair.inspect(path: zipPath)
            model.phase = .zipInspected
        default:
            model.phase = .idle
        }
    }

    /// 창 번호와, 메뉴바부터 창 아래까지 덮는 영역 (screencapture는 왼쪽 위가 원점)
    func printGeometry(panel: NSWindow) {
        let f = panel.frame
        let top = NSScreen.screens.first?.frame.maxY ?? f.maxY
        let region = "\(Int(f.minX) - 16),0,\(Int(f.width) + 32),\(Int(top - f.minY) + 16)"
        print("WINDOW \(panel.windowNumber)")
        print("REGION \(region)")
        fflush(stdout)
    }
}
