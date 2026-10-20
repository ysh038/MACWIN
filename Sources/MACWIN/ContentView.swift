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
                case .scanning: ProgressView("검사하는 중…").frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Text("윈도우로 보내기 전에 검토하기").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                if model.canUndo { Button("마지막 수정 되돌리기") { model.undo() } }
                Toggle("ZIP: 옛날 윈도우 호환 (CP949)", isOn: $model.legacyCP949)
                Divider()
                Button("MACWIN 정보") { AppIcon.showAbout() }
                Button("종료") { NSApp.terminate(nil) }
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
            Text("폴더나 파일을 여기에 놓으세요").font(.title3)
            Text("메뉴바 아이콘 위에 바로 놓아도 돼요").font(.callout).foregroundStyle(.secondary)
            Text("ZIP 파일을 놓으면 ZIP 안의 이름을 검사해요").font(.callout).foregroundStyle(.secondary)
            Button("선택…") { model.choose() }
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
                Text("\(r.scanned)개 검사").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            if r.findings.isEmpty {
                Spacer()
                Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(.green)
                Text("깨끗해요. 윈도우로 보내도 괜찮아요.").font(.title3).padding(.top, 8)
                junkNote.padding(.top, 12)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if !r.fixable.isEmpty {
                            HStack {
                                Text("고칠 것 \(r.fixable.count)개").font(.caption.weight(.semibold))
                                Spacer()
                                Button(model.selected.count == r.fixable.count ? "전체 해제" : "전체 선택") { model.toggleAll() }
                                    .buttonStyle(.link).font(.caption)
                            }
                            .padding(.top, 4)
                            ForEach(r.fixable) { f in FixRow(finding: f, selected: binding(for: f.id)) }
                        }
                        if !r.warnings.isEmpty {
                            Text("직접 확인할 것 \(r.warnings.count)개").font(.caption.weight(.semibold)).padding(.top, 10)
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
                Button("처음으로") { model.reset() }
                Spacer()
                // 원본은 그대로 두고 고친 이름으로 ZIP만 만들기
                Button {
                    model.makeZip()
                } label: {
                    Label("윈도우용 ZIP", systemImage: "doc.zipper")
                }
                .help("원본은 그대로 두고, 윈도우에서 안 깨지는 이름으로 ZIP을 원본 옆에 만들어요.")
                if !r.fixable.isEmpty {
                    Button {
                        model.scrub()
                    } label: {
                        Label("고치기 (\(model.selected.count))", systemImage: "checkmark")
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selected.isEmpty)
                    .help("원본 파일의 이름을 바로 고쳐요.")
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
                    Text("맥 숨김파일(.DS_Store, ._ 등) \(r.junkCount)개는 그대로 뒀어요. 윈도우에선 보일 수 있어요.")
                }
                if !r.skipped.isEmpty {
                    Text("안쪽은 검사 안 함: " + r.skipped.joined(separator: ", ")).lineLimit(2)
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
                    Text("원래: " + visible(finding.name)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
            Text("\(rep.done.count)개 고쳤어요").font(.title2)
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
                if model.canUndo { Button("되돌리기") { model.undo() } }
                Spacer()
                Button("다시 검사") { model.rescan() }
                Button("윈도우용 ZIP") { model.makeZip() }
                Button("완료") { model.reset() }.keyboardShortcut(.defaultAction)
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
                Text("항목 \(ins.entryCount)개 검사").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            if let why = ins.unsupported {
                Spacer()
                Image(systemName: "exclamationmark.triangle").font(.system(size: 44)).foregroundStyle(.orange)
                Text("이 ZIP은 고칠 수 없어요").font(.title3).padding(.top, 8)
                Text(why).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
                Spacer()
            } else if !ins.needsRepair {
                Spacer()
                Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(.green)
                Text("깨끗해요. 윈도우에서도 이름이 안 깨져요.").font(.title3).padding(.top, 8)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if ins.issues.contains(where: { $0.issues.contains(.zipNoUTF8Flag) }) {
                            Label("맥에서 만든 ZIP이라 윈도우에서 이름이 깨져요.", systemImage: "exclamationmark.triangle.fill")
                                .font(.callout).foregroundStyle(.orange).padding(.vertical, 4)
                        }
                        if !ins.issues.isEmpty {
                            Text("고칠 이름 \(ins.issues.count)개").font(.caption.weight(.semibold)).padding(.top, 4)
                            ForEach(ins.issues) { e in ZipEntryRow(entry: e) }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            if ins.junkCount > 0 { Text("맥 숨김파일(__MACOSX, ._ 등) \(ins.junkCount)개는 빼요.") }
                            if ins.encrypted { Text("암호가 걸린 ZIP이에요. 이름만 고치고 암호는 그대로 둬요.") }
                            Text("원본 ZIP은 그대로 두고, 옆에 \"(윈도우용)\" ZIP을 새로 만들어요.")
                        }
                        .font(.caption2).foregroundStyle(.secondary).padding(.top, 10)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }

            Divider()
            HStack {
                Button("처음으로") { model.reset() }
                Spacer()
                if ins.needsRepair {
                    Button {
                        model.repairZip()
                    } label: {
                        Label("윈도우용으로 고치기", systemImage: "doc.zipper")
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
                    Text("원래: " + visible(oldName)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
            Text("ZIP 만드는 중… \(Int(model.zipProgress * 100))%").foregroundStyle(.secondary)
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
                Text("ZIP을 만들지 못했어요").font(.title2)
                Text(error).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else {
                Image(systemName: "doc.zipper").font(.system(size: 44)).foregroundStyle(Color.accentColor)
                Text("윈도우용 ZIP을 만들었어요").font(.title2)
                Text((rep.output as NSString).lastPathComponent.precomposedStringWithCanonicalMapping)
                    .font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text("파일 \(rep.fileCount)개, 폴더 \(rep.dirCount)개")
                    if rep.renamed > 0 { Text("이름 \(rep.renamed)개를 윈도우용으로 바꿔 넣었어요") }
                    if rep.excludedJunk > 0 { Text("맥 숨김파일 \(rep.excludedJunk)개는 뺐어요") }
                    if !rep.skippedLinks.isEmpty { Text("바로가기(심볼릭 링크) \(rep.skippedLinks.count)개는 뺐어요") }
                    Text(model.legacyCP949 ? "이름 방식: 옛날 윈도우 호환 (CP949)" : "이름 방식: UTF-8 (윈도우 10·11)")
                        .foregroundStyle(.secondary)
                    Text("원본 파일은 그대로예요.").foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            Spacer()
            HStack {
                Button("처음으로") { model.reset() }
                Spacer()
                if model.zipError == nil {
                    Button("Finder에서 보기") { model.revealZip() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
        }
    }
}
