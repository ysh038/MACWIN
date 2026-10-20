import Foundation
import ScrubCore

// 테스트/터미널용: macwin-cli scan|fix <경로...>, macwin-cli undo
let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else {
    print("usage: macwin-cli scan|fix <paths...> | undo")
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
