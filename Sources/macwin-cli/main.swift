import Foundation
import ScrubCore

// 테스트/터미널용 도구. 출력은 영어
let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else {
    print("usage: macwin-cli scan|fix <paths...> | zip [--cp949] [-o out.zip] <paths...> | repair [--check] [--cp949] [-o out.zip] <file.zip> | undo")
    exit(1)
}

func printScan(_ r: ScanResult) {
    print("Checked \(r.scanned), Mac hidden files \(r.junkCount) (left as is)")
    for f in r.findings {
        let tags = f.issues.map(\.title).joined(separator: ",")
        if f.isFixable {
            print("  fix   [\(tags)] \(f.displayPath)" + (f.looksSame ? "" : "   (was: \(f.name))"))
        } else {
            print("  warn  [\(tags)] \(f.displayPath)")
        }
    }
    if !r.skipped.isEmpty { print("Not checked inside: \(r.skipped.joined(separator: ", "))") }
}

switch cmd {
case "scan":
    printScan(Scanner.scan(paths: Array(args.dropFirst())))
case "fix":
    let r = Scanner.scan(paths: Array(args.dropFirst()))
    printScan(r)
    let rep = Fixer.apply(r.findings)
    print("Renamed \(rep.done.count), failed \(rep.failed.count)")
    for f in rep.failed { print("  failed \(f.path): \(f.reason)") }
case "zip":
    // macwin-cli zip [--cp949] [-o out.zip] <paths...>
    var rest = Array(args.dropFirst())
    var options = ZipOptions()
    var output: String?
    if let i = rest.firstIndex(of: "--cp949") { options.legacyCP949 = true; rest.remove(at: i) }
    if let i = rest.firstIndex(of: "-o"), i + 1 < rest.count { output = rest[i + 1]; rest.removeSubrange(i...i + 1) }
    do {
        let rep = try Zipper.makeZip(paths: rest, to: output ?? Zipper.defaultOutputPath(for: rest), options: options)
        print("Created \(rep.output)")
        print("Files \(rep.fileCount), folders \(rep.dirCount), renamed \(rep.renamed), Mac hidden files removed \(rep.excludedJunk)")
        if !rep.skippedLinks.isEmpty { print("Links removed: \(rep.skippedLinks.joined(separator: ", "))") }
    } catch {
        print("Failed: \(error.localizedDescription)")
        exit(1)
    }
case "repair":
    // macwin-cli repair [--check] [--cp949] [-o out.zip] <existing.zip>
    var rest = Array(args.dropFirst())
    var options = ZipOptions()
    var output: String?
    var checkOnly = false
    if let i = rest.firstIndex(of: "--cp949") { options.legacyCP949 = true; rest.remove(at: i) }
    if let i = rest.firstIndex(of: "--check") { checkOnly = true; rest.remove(at: i) }
    if let i = rest.firstIndex(of: "-o"), i + 1 < rest.count { output = rest[i + 1]; rest.removeSubrange(i...i + 1) }
    guard let path = rest.first else { print("A ZIP path is required"); exit(1) }
    let ins = ZipRepair.inspect(path: path)
    if let why = ins.unsupported { print("Can't fix: \(why)"); exit(1) }
    print("Entries \(ins.entryCount), issues \(ins.issues.count), Mac hidden files \(ins.junkCount)" + (ins.encrypted ? ", encrypted" : ""))
    for f in ins.issues {
        let tags = f.issues.map(\.title).joined(separator: ",")
        print("  [\(tags)] \(f.newPath)" + (f.looksSame ? "" : "   (was: \(f.originalPath))"))
    }
    if checkOnly { break }
    do {
        let rep = try ZipRepair.repair(path: path, to: output ?? ZipRepair.defaultOutputPath(for: path), options: options)
        print("Created \(rep.output)")
        print("Files \(rep.fileCount), folders \(rep.dirCount), renamed \(rep.renamed), Mac hidden files removed \(rep.excludedJunk)")
    } catch {
        print("Failed: \(error.localizedDescription)")
        exit(1)
    }
case "undo":
    guard let last = History.loadLast() else { print("Nothing to undo"); exit(1) }
    let rep = Fixer.undo(last)
    if rep.failed.isEmpty { History.clearLast() }
    print("Restored \(rep.done.count), failed \(rep.failed.count)")
    for f in rep.failed { print("  failed \(f.path): \(f.reason)") }
default:
    print("unknown command \(cmd)")
    exit(1)
}
