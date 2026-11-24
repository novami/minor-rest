import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum BodyMode: String, CaseIterable {
    case pretty, raw, preview
}

/// Tělo odpovědi v pohledu Pretty / Raw / Náhled; `bar` = záložkový pruh odpovědi.
struct ResponseBodyPane<Bar: View>: View {
    let tabID: String
    let run: RunStore.Run
    let result: RunResult
    @ViewBuilder let bar: Bar
    @State private var findTrigger = 0
    @Environment(AppModel.self) private var model
    @Environment(\.appFonts) private var fonts

    var body: some View {
        let modes = availableModes
        let mode = run.mode.flatMap { modes.contains($0) ? $0 : nil } ?? defaultMode(modes)
        let filter = filterText
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                bar
                Spacer()
                if canFilter { filterField }
                if modes.count > 1 {
                    Picker("", selection: Binding(get: { mode }, set: { model.runs.setMode(tabID, $0) })) {
                        ForEach(modes, id: \.self) { Text(t("response.mode.\($0.rawValue)")).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(filter != nil)
                }
                if mode != .preview || filter != nil, run.body != nil, !result.isBinary {
                    Button { findTrigger += 1 } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.borderless)
                        .help(t("response.find"))
                }
                if run.body != nil {
                    if !result.isBinary {
                        Button { copyText(shown(mode)?.text ?? "") } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless)
                            .help(t("response.copyBody"))
                    }
                    Button { saveBody() } label: { Image(systemName: "square.and.arrow.down") }
                        .buttonStyle(.borderless)
                        .help(t("response.saveBody"))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            notice(mode)
            content(mode)
        }
        .task(id: run.runID + mode.rawValue + String(run.forcePretty)) {
            if mode == .pretty, autoPretty || run.forcePretty { await model.runs.loadPretty(tabID) }
        }
        .task(id: run.runID + String(canFilter) + model.runs.filters[tabID, default: ""]) {
            guard canFilter else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await model.runs.applyFilter(tabID)
        }
    }

    // MARK: Filtr

    private var canFilter: Bool { run.body?.lang == "json" && run.body?.partial == false && !result.isBinary }

    private var filterExpr: String { model.runs.filters[tabID, default: ""].trimmingCharacters(in: .whitespaces) }

    /// Výsledek filtru platný pro aktuální výraz; nil = filtr se nepoužije.
    private var filterText: String? {
        guard canFilter, !filterExpr.isEmpty, let fn = run.filtered, fn.expr == filterExpr else { return nil }
        return fn.text
    }

    private var filterError: String? {
        guard canFilter, let fn = run.filtered, fn.expr == filterExpr else { return nil }
        return fn.error
    }

    private var filterField: some View {
        let err = filterError
        return TextField("", text: Binding(get: { model.runs.filters[tabID, default: ""] },
                                           set: { model.runs.filters[tabID] = $0 }),
                         prompt: Text(t("response.filter.placeholder")))
            .textFieldStyle(.roundedBorder)
            .font(fonts.code)
            .frame(minWidth: 140, idealWidth: 220, maxWidth: 320)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.red, lineWidth: err == nil ? 0 : 1.5))
            .help(err ?? t("response.filter.help"))
    }

    // MARK: Obsah

    /// Text pro zobrazení / kopírování v daném režimu.
    private func shown(_ mode: BodyMode) -> BodyView? {
        if let fn = filterText, var val = run.body {
            val.text = fn
            return val
        }
        if mode == .pretty, let par = run.pretty { return par }
        if mode == .pretty, !autoPretty, !run.forcePretty { return run.body }
        return mode == .pretty ? nil : run.body
    }

    /// Pretty se spouští automaticky jen do `BodyView.autoPretty`.
    private var autoPretty: Bool { (run.body?.size ?? 0) <= BodyView.autoPretty }

    @ViewBuilder private func notice(_ mode: BodyMode) -> some View {
        if let buf = run.body, buf.partial {
            noticeBar(t("response.partial", ["head": fmtBytes(Int64(BodyView.headView)), "size": fmtBytes(buf.size)])) {
                Button(t("response.saveBody")) { saveBody() }
            }
        } else if result.truncated {
            noticeBar(t("response.truncated")) { Button(t("response.saveBody")) { saveBody() } }
        } else if mode == .pretty, filterText == nil, let buf = run.body, !autoPretty, !run.forcePretty {
            noticeBar(t("response.bigBody", ["size": fmtBytes(buf.size)])) {
                Button(t("response.formatAnyway")) { model.runs.forcePretty(tabID) }
            }
        }
    }

    private func noticeBar(_ text: String, @ViewBuilder action: () -> some View) -> some View {
        HStack(spacing: 8) {
            Label(text, systemImage: "info.circle").foregroundStyle(.secondary)
            action().controlSize(.small)
            Spacer(minLength: 0)
        }
        .font(fonts.small)
        .padding(.horizontal, 10).padding(.bottom, 4)
    }

    @ViewBuilder private func content(_ mode: BodyMode) -> some View {
        if result.isBinary {
            if let data = run.body?.image {
                ImagePreview(data: data)
            } else {
                let key = result.contentType.hasPrefix("image/") ? "response.imageTooLarge" : "response.binary"
                VStack(spacing: 8) {
                    EmptyState(title: t(key, ["type": result.contentType.isEmpty ? "?" : result.contentType,
                                              "size": fmtBytes(result.sizes.bodyDecoded)]))
                        .frame(maxHeight: 40)
                    Button(t("response.saveBody")) { saveBody() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if mode == .preview, filterText == nil, let buf = run.body {
            HTMLPreviewView(html: HTMLPreview.sandboxed(buf.text)).id(run.runID)
        } else if let buf = shown(mode) {
            CodeTextView(text: .constant(buf.text), lang: SyntaxLang(rawValue: buf.lang) ?? .text,
                         editable: false, font: fonts.codeNSFont, findTrigger: findTrigger)
                .id(run.runID + mode.rawValue + (filterText == nil ? "" : "f" + filterExpr) + String(run.pretty != nil))
        } else if run.body != nil {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Spacer(minLength: 0)
        }
    }

    private var availableModes: [BodyMode] {
        if result.isBinary || run.body?.partial == true { return [] }
        switch run.body?.lang {
        case "html": return [.pretty, .raw, .preview]
        case "json", "xml": return [.pretty, .raw]
        default: return [.raw]
        }
    }

    private func defaultMode(_ modes: [BodyMode]) -> BodyMode {
        if result.isBinary { return .preview }
        return modes.first ?? .raw
    }

    // MARK: Uložení

    private func saveBody() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.runs.saveBody(tabID, to: url) }
    }

    /// Název souboru z posledního segmentu URL, přípona dle Content-Type.
    private var suggestedName: String {
        let last = URL(string: result.sent.url)?.lastPathComponent ?? ""
        var name = last.isEmpty || last == "/" ? "response" : last
        if (name as NSString).pathExtension.isEmpty,
           let ext = UTType(mimeType: result.contentType)?.preferredFilenameExtension {
            name += "." + ext
        }
        return name
    }
}

/// Náhled obrázku v přirozené velikosti (zmenšený do panelu).
struct ImagePreview: View {
    let data: Data

    var body: some View {
        if let img = NSImage(data: data) {
            Image(nsImage: img)
                .resizable().scaledToFit()
                .frame(maxWidth: img.size.width, maxHeight: img.size.height)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyState(title: t("response.imageInvalid"))
        }
    }
}
