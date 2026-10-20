import SwiftUI
import UniformTypeIdentifiers
import ScrubCore

struct ContentView: View {
    @ObservedObject var model: ScrubModel
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch model.phase {
                case .idle: IdleView(model: model, targeted: targeted)
                case .scanning: ProgressView(tr("Checking…")).frame(maxWidth: .infinity, maxHeight: .infinity)
                case .scanned: ScannedView(model: model)
                case .done: DoneView(model: model)
                case .zipInspected: ZipInspectView(model: model)
                case .zipping: ZippingView(model: model)
                case .zipped: ZippedView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 420, height: 500)
        // 어느 화면에서든 창에 놓으면 새로 검사
        .overlay {
            if targeted && model.phase != .idle {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.08)))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            guard model.phase != .zipping else { return false }
            loadURLs(providers) { model.scan($0) }
            return true
        }
    }

    private var header: some View {
        HStack {
            Image(nsImage: AppIcon.logo(size: 28))
            VStack(alignment: .leading, spacing: 1) {
                Text("MACWIN").font(.headline)
                Text(tr("Check before sending to Windows")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                if model.canUndo { Button(tr("Undo Last Fix")) { model.undo() } }
                Toggle(tr("ZIP: Legacy Windows (CP949)"), isOn: $model.legacyCP949)
                Divider()
                Button(tr("About MACWIN")) { AppIcon.showAbout() }
                Button(tr("Quit")) { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(12)
    }
}

// MARK: - 처음 화면

private struct IdleView: View {
    @ObservedObject var model: ScrubModel
    let targeted: Bool

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "tray.and.arrow.down").font(.system(size: 40)).foregroundStyle(.secondary)
            Text(tr("Drop folders or files here")).font(.title3)
            Text(tr("You can also drop them on the menu bar icon")).font(.callout).foregroundStyle(.secondary)
            Text(tr("Drop a ZIP file to check the names inside it")).font(.callout).foregroundStyle(.secondary)
            Button(tr("Choose…")) { model.choose() }
            if let notice = model.notice {
                Text(notice).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.4))
                .background(RoundedRectangle(cornerRadius: 12).fill(targeted ? Color.accentColor.opacity(0.08) : .clear))
        )
        .padding(16)
    }
}

func loadURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    var urls: [URL] = []
    let group = DispatchGroup()
    let lock = NSLock()
    for p in providers {
        group.enter()
        p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                lock.lock(); urls.append(url); lock.unlock()
            }
            group.leave()
        }
    }
    group.notify(queue: .main) { if !urls.isEmpty { completion(urls) } }
}

// MARK: - 검사 결과

private struct ScannedView: View {
    @ObservedObject var model: ScrubModel

    var body: some View {
        let r = model.result
        VStack(spacing: 0) {
            HStack {
                Text(r.roots.joined(separator: ", ")).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(tr("Checked %ld items", r.scanned)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            if r.findings.isEmpty {
                Spacer()
                Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(.green)
                Text(tr("All clean. Safe to send to Windows.")).font(.title3).padding(.top, 8)
                junkNote.padding(.top, 12)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if !r.fixable.isEmpty {
                            HStack {
                                Text(tr("To fix: %ld", r.fixable.count)).font(.caption.weight(.semibold))
                                Spacer()
                                Button(model.selected.count == r.fixable.count ? tr("Deselect All") : tr("Select All")) { model.toggleAll() }
                                    .buttonStyle(.link).font(.caption)
                            }
                            .padding(.top, 4)
                            ForEach(r.fixable) { f in FixRow(finding: f, selected: binding(for: f.id)) }
                        }
                        if !r.warnings.isEmpty {
                            Text(tr("Check yourself: %ld", r.warnings.count)).font(.caption.weight(.semibold)).padding(.top, 10)
                            ForEach(r.warnings) { f in WarnRow(finding: f) }
                        }
                        junkNote.padding(.top, 10)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }

            Divider()
            HStack {
                Button(tr("Start Over")) { model.reset() }
                Spacer()
                // 원본은 그대로 두고 고친 이름으로 ZIP만 만들기
                Button {
                    model.makeZip()
                } label: {
                    Label(tr("Windows ZIP"), systemImage: "doc.zipper")
                }
                .help(tr("Creates a ZIP with Windows-safe names next to the originals, without touching them."))
                if !r.fixable.isEmpty {
                    Button {
                        model.scrub()
                    } label: {
                        Label(tr("Fix (%ld)", model.selected.count), systemImage: "checkmark")
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selected.isEmpty)
                    .help(tr("Renames the original files right away."))
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder private var junkNote: some View {
        let r = model.result
        if r.junkCount > 0 || !r.skipped.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                if r.junkCount > 0 {
                    Text(tr("Left %ld Mac hidden files (.DS_Store, ._ etc.) as they are. They may be visible on Windows.", r.junkCount))
                }
                if !r.skipped.isEmpty {
                    Text(tr("Not checked inside: %@", r.skipped.joined(separator: ", "))).lineLimit(2)
                }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func binding(for id: Int) -> Binding<Bool> {
        Binding(get: { model.selected.contains(id) },
                set: { on in if on { model.selected.insert(id) } else { model.selected.remove(id) } })
    }
}

private struct FixRow: View {
    let finding: Finding
    @Binding var selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $selected).labelsHidden().toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 2) {
                PathText(path: finding.displayPath, isDirectory: finding.isDirectory)
                if !finding.looksSame {
                    Text(tr("Original: %@", visible(finding.name))).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Chips(issues: finding.issues)
            }
        }
        .padding(.vertical, 3)
        .help(finding.issues.map(\.detail).joined(separator: "\n"))
    }
}

private struct WarnRow: View {
    let finding: Finding

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                PathText(path: finding.displayPath, isDirectory: finding.isDirectory)
                Text(finding.issues.filter { !$0.isFixable }.map(\.detail).joined(separator: " "))
                    .font(.caption).foregroundStyle(.secondary)
                Chips(issues: finding.issues)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct PathText: View {
    let path: String
    let isDirectory: Bool

    var body: some View {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        let dir = parts.dropLast().joined(separator: "/")
        let name = String(parts.last ?? "")
        (Text(dir.isEmpty ? "" : dir + "/").foregroundColor(.secondary)
            + Text(name + (isDirectory ? "/" : "")).fontWeight(.medium))
            .font(.callout)
            .lineLimit(2)
            .truncationMode(.head)
    }
}

private struct Chips: View {
    let issues: [IssueKind]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(issues, id: \.self) { k in
                Text(k.title)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill((k.isFixable ? Color.accentColor : Color.orange).opacity(0.15)))
            }
        }
    }
}

/// 보이지 않는 문자를 눈에 보이게 표시
private func visible(_ s: String) -> String {
    var out = ""
    for u in s.precomposedStringWithCanonicalMapping.unicodeScalars {
        switch u.value {
        case 0x00..<0x20, 0x7F, 0x00A0, 0x2000...0x200D, 0x202F, 0x205F, 0x2060, 0xFEFF:
            out += String(format: "‹U+%04X›", u.value)
        default:
            out.unicodeScalars.append(u)
        }
    }
    return out
}

// MARK: - 완료

private struct DoneView: View {
    @ObservedObject var model: ScrubModel

    var body: some View {
        let rep = model.report
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: rep.failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(rep.failed.isEmpty ? Color.accentColor : .orange)
            Text(tr("Fixed %ld items", rep.done.count)).font(.title2)
            if !rep.failed.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(rep.failed.enumerated()), id: \.offset) { _, f in
                            Text("\(f.path): \(f.reason)").font(.caption)
                        }
                    }
                }
                .frame(maxHeight: 120)
                .padding(.horizontal, 16)
            }
            Spacer()
            HStack {
                if model.canUndo { Button(tr("Undo")) { model.undo() } }
                Spacer()
                Button(tr("Check Again")) { model.rescan() }
                Button(tr("Windows ZIP")) { model.makeZip() }
                Button(tr("Done")) { model.reset() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
    }
}

// MARK: - ZIP

/// ZIP 파일 하나를 올렸을 때: ZIP 안의 이름 검사 결과
private struct ZipInspectView: View {
    @ObservedObject var model: ScrubModel

    var body: some View {
        let ins = model.zipInspection
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "doc.zipper").foregroundStyle(.secondary)
                Text((ins.path as NSString).lastPathComponent.precomposedStringWithCanonicalMapping)
                    .font(.subheadline.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(tr("Checked %ld entries", ins.entryCount)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            if let why = ins.unsupported {
                Spacer()
                Image(systemName: "exclamationmark.triangle").font(.system(size: 44)).foregroundStyle(.orange)
                Text(tr("This ZIP can't be fixed")).font(.title3).padding(.top, 8)
                Text(why).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
                Spacer()
            } else if !ins.needsRepair {
                Spacer()
                Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(.green)
                Text(tr("All clean. Names won't break on Windows.")).font(.title3).padding(.top, 8)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if ins.issues.contains(where: { $0.issues.contains(.zipNoUTF8Flag) }) {
                            Label(tr("This ZIP was made on a Mac, so names will be garbled on Windows."), systemImage: "exclamationmark.triangle.fill")
                                .font(.callout).foregroundStyle(.orange).padding(.vertical, 4)
                        }
                        if !ins.issues.isEmpty {
                            Text(tr("Names to fix: %ld", ins.issues.count)).font(.caption.weight(.semibold)).padding(.top, 4)
                            ForEach(ins.issues) { e in ZipEntryRow(entry: e) }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            if ins.junkCount > 0 { Text(tr("%ld Mac hidden files (__MACOSX, ._ etc.) will be removed.", ins.junkCount)) }
                            if ins.encrypted { Text(tr("This ZIP is password-protected. Only names are fixed; the password stays the same.")) }
                            Text(tr("The original ZIP is kept. A new \"(for Windows)\" ZIP is created next to it."))
                        }
                        .font(.caption2).foregroundStyle(.secondary).padding(.top, 10)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }

            Divider()
            HStack {
                Button(tr("Start Over")) { model.reset() }
                Spacer()
                if ins.needsRepair {
                    Button {
                        model.repairZip()
                    } label: {
                        Label(tr("Fix for Windows"), systemImage: "doc.zipper")
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
        }
    }
}

private struct ZipEntryRow: View {
    let entry: ZipEntryIssue

    var body: some View {
        let newPath = entry.isDirectory ? String(entry.newPath.dropLast()) : entry.newPath
        let oldName = (entry.isDirectory ? String(entry.originalPath.dropLast()) : entry.originalPath)
            .split(separator: "/").last.map(String.init) ?? entry.originalPath
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.isDirectory ? "folder" : "doc").foregroundStyle(.secondary).frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                PathText(path: newPath, isDirectory: entry.isDirectory)
                if !entry.looksSame && !(newPath.hasSuffix("/" + oldName) || newPath == oldName) {
                    Text(tr("Original: %@", visible(oldName))).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Chips(issues: entry.issues)
            }
        }
        .padding(.vertical, 3)
        .help(entry.issues.map(\.detail).joined(separator: "\n"))
    }
}

private struct ZippingView: View {
    @ObservedObject var model: ScrubModel

    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: model.zipProgress)
                .frame(width: 260)
            Text(tr("Creating ZIP… %ld%%", Int(model.zipProgress * 100))).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ZippedView: View {
    @ObservedObject var model: ScrubModel

    var body: some View {
        let rep = model.zipReport
        VStack(spacing: 12) {
            Spacer()
            if let error = model.zipError {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 44)).foregroundStyle(.orange)
                Text(tr("Couldn't create the ZIP")).font(.title2)
                Text(error).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else {
                Image(systemName: "doc.zipper").font(.system(size: 44)).foregroundStyle(Color.accentColor)
                Text(tr("Created a Windows ZIP")).font(.title2)
                Text((rep.output as NSString).lastPathComponent.precomposedStringWithCanonicalMapping)
                    .font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("%ld files, %ld folders", rep.fileCount, rep.dirCount))
                    if rep.renamed > 0 { Text(tr("Renamed %ld items for Windows", rep.renamed)) }
                    if rep.excludedJunk > 0 { Text(tr("Removed %ld Mac hidden files", rep.excludedJunk)) }
                    if !rep.skippedLinks.isEmpty { Text(tr("Removed %ld symbolic links", rep.skippedLinks.count)) }
                    Text(model.legacyCP949 ? tr("Name encoding: Legacy Windows (CP949)") : tr("Name encoding: UTF-8 (Windows 10/11)"))
                        .foregroundStyle(.secondary)
                    Text(tr("The original files are unchanged.")).foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            Spacer()
            HStack {
                Button(tr("Start Over")) { model.reset() }
                Spacer()
                if model.zipError == nil {
                    Button(tr("Show in Finder")) { model.revealZip() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
        }
    }
}
