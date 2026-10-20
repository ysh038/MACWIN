import Foundation
import ScrubCore

// 테스트/터미널용: macwin-cli scan|fix <경로...>, macwin-cli undo
let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else {
    print("usage: macwin-cli scan|fix <paths...> | zip [--cp949] [-o out.zip] <paths...> | undo")
    exit(1)
}

func printScan(_ r: ScanResult) {
    print("검사 \(r.scanned)개, 맥 숨김파일 \(r.junkCount)개(그대로 둠)")
    for f in r.findings {
        let tags = f.issues.map(\.title).joined(separator: ",")
        if f.isFixable {
            print("  고침  [\(tags)] \(f.displayPath)" + (f.looksSame ? "" : "   (원래: \(f.name))"))
        } else {
            print("  경고  [\(tags)] \(f.displayPath)")
        }
    }
    if !r.skipped.isEmpty { print("안쪽 검사 안 함: \(r.skipped.joined(separator: ", "))") }
}

switch cmd {
case "scan":
    printScan(Scanner.scan(paths: Array(args.dropFirst())))
case "fix":
    let r = Scanner.scan(paths: Array(args.dropFirst()))
    printScan(r)
    let rep = Fixer.apply(r.findings)
    print("바꿈 \(rep.done.count)개, 실패 \(rep.failed.count)개")
    for f in rep.failed { print("  실패 \(f.path): \(f.reason)") }
case "zip":
    // macwin-cli zip [--cp949] [-o 출력.zip] <paths...>
    var rest = Array(args.dropFirst())
    var options = ZipOptions()
    var output: String?
    if let i = rest.firstIndex(of: "--cp949") { options.legacyCP949 = true; rest.remove(at: i) }
    if let i = rest.firstIndex(of: "-o"), i + 1 < rest.count { output = rest[i + 1]; rest.removeSubrange(i...i + 1) }
    do {
        let rep = try Zipper.makeZip(paths: rest, to: output ?? Zipper.defaultOutputPath(for: rest), options: options)
        print("만듦 \(rep.output)")
        print("파일 \(rep.fileCount)개, 폴더 \(rep.dirCount)개, 이름 바꿈 \(rep.renamed)개, 맥 숨김파일 뺌 \(rep.excludedJunk)개")
        if !rep.skippedLinks.isEmpty { print("링크 뺌: \(rep.skippedLinks.joined(separator: ", "))") }
    } catch {
        print("실패: \(error.localizedDescription)")
        exit(1)
    }
case "undo":
    guard let last = History.loadLast() else { print("되돌릴 기록 없음"); exit(1) }
    let rep = Fixer.undo(last)
    if rep.failed.isEmpty { History.clearLast() }
    print("되돌림 \(rep.done.count)개, 실패 \(rep.failed.count)개")
    for f in rep.failed { print("  실패 \(f.path): \(f.reason)") }
default:
    print("unknown command \(cmd)")
    exit(1)
}
