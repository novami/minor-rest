import MinorRESTCore
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
        .sheet(item: $opened) { VersionSheet(opened: $0) }
        .sheet(item: $diff) { DiffSheet(content: $0) }
    }

    /// Starší vybraná verze → novější.
    private func compare() {
        let pair = selection.sorted()
        guard pair.count == 2 else { return }
        Task {
            guard let a = await model.runs.version(projectID, requestID, pair[0]),
                  let b = await model.runs.version(projectID, requestID, pair[1]) else { return }
            let lines = LineDiff.diff(LineDiff.text(a.0, body: a.1), LineDiff.text(b.0, body: b.1))
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
                    if let (e, b) = await model.runs.version(projectID, requestID, i.version) {
                        opened = Opened(id: i.version, entry: e, body: b)
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
        guard let d = ISO8601DateFormatter().date(from: rfc3339) else { return rfc3339 }
        return d.formatted(date: .abbreviated, time: .standard)
    }
}

/// Uložená verze jen pro čtení: stav, hlavičky a tělo.
private struct VersionSheet: View {
    let opened: VersionsView.Opened
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appFonts) private var fonts

    var body: some View {
        let e = opened.entry
        VStack(alignment: .leading, spacing: 8) {
            Text(t("versions.title", ["n": String(opened.id)])).font(.headline)
            HStack(spacing: 8) {
                Text(e.request.method).bold()
                Text(e.request.url).lineLimit(1).truncationMode(.middle)
            }
            .font(fonts.code).textSelection(.enabled)
            Text("\(e.response.status) \(e.response.statusText) · \(e.response.proto) · \(VersionsView.time(e.savedAt))")
                .foregroundStyle(.secondary)
            VSplitView {
                HeaderTable(rows: e.response.headers, empty: t("response.headers.none")).frame(minHeight: 80)
                ScrollView {
                    Text(String(decoding: opened.body.prefix(1 << 20), as: UTF8.self))
                        .font(fonts.code).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                .frame(minHeight: 120)
            }
            HStack { Spacer(); Button(t("common.close")) { dismiss() }.keyboardShortcut(.cancelAction) }
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
