import AppKit
import MinorRESTCore
import SwiftUI

enum BodyMode: String, CaseIterable {
    case pretty, raw, preview
}

/// Záložky odpovědi (zatím jen Tělo) a tělo v pohledu Pretty / Raw / Náhled.
struct ResponseBodyPane: View {
    let tabID: String
    let run: RunStore.Run
    let result: RunResult
    @State private var findTrigger = 0
    @Environment(AppModel.self) private var model
    @Environment(\.appFonts) private var fonts

    var body: some View {
        let modes = availableModes
        let mode = run.mode.flatMap { modes.contains($0) ? $0 : nil } ?? defaultMode(modes)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(t("response.tab.body"))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.primary.opacity(0.1), in: .rect(cornerRadius: 5))
                Spacer()
                if modes.count > 1 {
                    Picker("", selection: Binding(get: { mode }, set: { model.runs.setMode(tabID, $0) })) {
                        ForEach(modes, id: \.self) { Text(t("response.mode.\($0.rawValue)")).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                if mode != .preview, run.body != nil {
                    Button { findTrigger += 1 } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.borderless)
                        .help(t("response.find"))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            if let b = run.body, b.partial {
                Text(t("response.partial", ["size": fmtBytes(b.size)]))
                    .font(fonts.small).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.bottom, 4)
            }
            content(mode)
        }
        .task(id: run.runID + mode.rawValue) {
            if mode == .pretty { await model.runs.loadPretty(tabID) }
        }
    }

    @ViewBuilder private func content(_ mode: BodyMode) -> some View {
        if result.isBinary {
            if let data = run.body?.image {
                ImagePreview(data: data)
            } else if result.contentType.hasPrefix("image/") {
                EmptyState(title: t("response.imageTooLarge", ["size": fmtBytes(result.sizes.bodyDecoded)]))
            } else {
                EmptyState(title: t("response.binary", ["size": fmtBytes(result.sizes.bodyDecoded)]))
            }
        } else if mode == .preview, let b = run.body {
            HTMLPreviewView(html: HTMLPreview.sandboxed(b.text)).id(run.runID)
        } else if let b = mode == .pretty ? run.pretty : run.body {
            CodeTextView(text: .constant(b.text), lang: SyntaxLang(rawValue: b.lang) ?? .text,
                         editable: false, font: fonts.codeNSFont, findTrigger: findTrigger)
                .id(run.runID + mode.rawValue)
        } else if run.body != nil {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Spacer(minLength: 0)
        }
    }

    private var availableModes: [BodyMode] {
        if result.isBinary { return [] }
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
}

/// Náhled obrázku v přirozené velikosti (zmenšený do panelu).
struct ImagePreview: View {
    let data: Data

    var body: some View {
        if let img = NSImage(data: data) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: img.size.width, maxHeight: img.size.height)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyState(title: t("response.imageInvalid"))
        }
    }
}
