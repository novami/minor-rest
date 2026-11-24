import SwiftUI

/// Záložka Verze: uložení aktuální odpovědi a seznam uložených verzí requestu.
struct VersionsView: View {
    let tabID: String
    let projectID: String
    let requestID: String
    @Environment(AppModel.self) private var model
    @Environment(\.appFonts) private var fonts
    @State private var opened: Opened?
    @State private var selection = Set<Int>()
    @State private var diff: DiffSheet.Content?
    @State private var editing: Int?
    @State private var labelText = ""

    struct Opened: Identifiable {
        let id: Int
        let entry: SavedResponse
        let body: Data
    }

    private var items: [SavedInfo] { model.runs.versions[RunStore.key(projectID, requestID)] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(t("versions.save")) {
                    Task { await model.runs.saveResponse(tabID, projectID: projectID, requestID: requestID) }
                }
                .disabled(model.runs.run(tabID)?.entry == nil)
                Button(t("versions.compare")) { compare() }
                    .disabled(selection.count != 2)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.bottom, 6)
            if items.isEmpty {
                Text(t("versions.empty")).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items, selection: $selection) { row($0) }.listStyle(.plain)
            }
        }
        .task(id: requestID) { await model.runs.loadVersions(projectID, requestID) }
        .sheet(item: $opened) { SavedResponseSheet(title: t("versions.title", ["n": String($0.id)]), entry: $0.entry, data: $0.body) }
        .sheet(item: $diff) { DiffSheet(content: $0) }
    }

    /// Starší vybraná verze → novější.
    private func compare() {
        let pair = selection.sorted()
        guard pair.count == 2 else { return }
        Task {
            guard let arg = await model.runs.version(projectID, requestID, pair[0]),
                  let buf = await model.runs.version(projectID, requestID, pair[1]) else { return }
            let lines = LineDiff.diff(LineDiff.text(arg.0, body: arg.1), LineDiff.text(buf.0, body: buf.1))
            let changed = lines.contains { $0.kind != .same }
            diff = DiffSheet.Content(from: pair[0], to: pair[1], text: changed ? LineDiff.render(lines) : "")
        }
    }

    private func row(_ i: SavedInfo) -> some View {
        HStack(spacing: 10) {
            Text("v\(i.version)").font(fonts.code).bold().frame(width: 52, alignment: .leading)
            Text(i.status > 0 ? String(i.status) : "–").font(fonts.code).frame(width: 40, alignment: .leading)
            Text(Self.time(i.savedAt)).foregroundStyle(.secondary)
            if editing == i.version {
                TextField(t("versions.label"), text: $labelText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let text = labelText
                        editing = nil
                        Task { await model.runs.setLabel(projectID, requestID, i.version, text) }
                    }
                    .onExitCommand { editing = nil }
            } else {
                Text(i.label.isEmpty ? t("versions.nolabel") : i.label)
                    .foregroundStyle(i.label.isEmpty ? .tertiary : .primary)
                    .onTapGesture(count: 2) { labelText = i.label; editing = i.version }
            }
            Spacer()
            Text(DisplayFormat.bytes(i.bodySize, locale: Locale(identifier: L10n.shared.code))).foregroundStyle(.secondary)
            Button(t("versions.open")) {
                Task {
                    if let (elem, buf) = await model.runs.version(projectID, requestID, i.version) {
                        opened = Opened(id: i.version, entry: elem, body: buf)
                    }
                }
            }
            Button(role: .destructive) {
                Task { await model.runs.deleteVersion(projectID, requestID, i.version) }
            } label: { Image(systemName: "trash") }
                .help(t("versions.delete"))
        }
        .buttonStyle(.borderless)
    }

    static func time(_ rfc3339: String) -> String {
        guard let dat = ISO8601DateFormatter().date(from: rfc3339) else { return rfc3339 }
        return dat.formatted(date: .abbreviated, time: .standard)
    }
}

/// Uložená odpověď (verze nebo záznam historie) jen pro čtení: stav, hlavičky a tělo.
struct SavedResponseSheet: View {
    let title: String
    let entry: SavedResponse
    let data: Data
    var openRequest: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appFonts) private var fonts
    @Environment(AppModel.self) private var model
    private var toasts: ToastCenter { model.toasts }

    var body: some View {
        let elem = entry
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            HStack(spacing: 8) {
                Text(elem.request.method).bold()
                Text(elem.request.url).lineLimit(1).truncationMode(.middle)
            }
            .font(fonts.code).textSelection(.enabled)
            Text(elem.error.isEmpty
                 ? "\(elem.response.status) \(elem.response.statusText) · \(elem.response.proto) · \(VersionsView.time(elem.savedAt))"
                 : "\(errorText(code: elem.error)) · \(VersionsView.time(elem.savedAt))")
                .foregroundStyle(.secondary)
            VSplitView {
                HeaderTable(rows: elem.response.headers, empty: t("response.headers.none")).frame(minHeight: 80)
                ScrollView {
                    Text(String(decoding: data.prefix(1 << 20), as: UTF8.self))
                        .font(fonts.code).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                .frame(minHeight: 120)
            }
            HStack {
                if let openRequest {
                    Button(t("history.openRequest")) { dismiss(); openRequest() }
                }
                Button(t("curl.copy")) {
                    copyText(Export.curl(entry))
                    toasts.show(t("curl.copied"))
                }
                Spacer()
                Button(t("common.close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 720, height: 560)
    }
}

/// Diff dvou verzí (starší → novější) v `CodeTextView`.
private struct DiffSheet: View {
    struct Content: Identifiable {
        let from: Int
        let to: Int
        let text: String
        var id: String { "\(from)-\(to)" }
    }

    let content: Content
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appFonts) private var fonts

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("versions.diff", ["a": String(content.from), "b": String(content.to)])).font(.headline)
            if content.text.isEmpty {
                Text(t("versions.nodiff")).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CodeTextView(text: .constant(content.text), lang: .diff, editable: false, font: fonts.codeNSFont)
            }
            HStack { Spacer(); Button(t("common.close")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(16)
        .frame(width: 720, height: 560)
    }
}
