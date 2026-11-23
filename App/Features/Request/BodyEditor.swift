import AppKit
import MinorRESTCore
import SwiftUI

/// Tělo requestu: přepínač typu (data ostatních typů zůstávají), raw = `CodeTextView` (+ Formátovat a varování
/// u JSON), form/multipart = `KvEditor`, binary = výběr souboru. Cesty k souborům přes `Project.fileRef`.
struct BodyEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appFonts) private var fonts
    @Binding var requestBody: Body
    let tabID: String
    let projectID: String

    private var type: String { requestBody.type.isEmpty ? BodyType.none : requestBody.type }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("", selection: Binding(get: { type }, set: { requestBody.type = $0 })) {
                    ForEach(BodyType.all, id: \.self) { Text(t("body.type.\($0)")).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .labelsHidden()
                Spacer()
                if type == BodyType.json {
                    Button(t("body.format"), action: format)
                }
            }
            .frame(height: 24)
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if let lang = SyntaxLang(bodyType: type) {
            CodeTextView(text: $requestBody.raw, lang: lang, font: fonts.codeNSFont)
                .id(tabID)   // vlastní undo na tab
                .frame(minHeight: 120, maxHeight: .infinity)
            if type == BodyType.json, let warning = jsonWarning {
                Text("⚠ \(warning)")
                    .font(fonts.small)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(warning)
            }
        } else if type == BodyType.form {
            ScrollView { KvEditor(rows: $requestBody.form) }
        } else if type == BodyType.multipart {
            ScrollView {
                KvEditor(rows: $requestBody.multipart, noteTitle: t("kv.contentType"),
                         valueCell: { part, ghost in AnyView(multipartValue(part, ghost)) })
            }
        } else if type == BodyType.binary {
            HStack(spacing: 8) {
                FileButton(path: requestBody.binaryPath, pick: { await pick($0) }) { requestBody.binaryPath = $0 }
                    .fixedSize()
                if !requestBody.binaryPath.isEmpty {
                    Button { requestBody.binaryPath = "" } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help(t("kv.delete"))
                }
                Spacer()
            }
            Spacer()
        } else {
            Text(t("body.none")).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func multipartValue(_ part: Binding<MultipartPart>, _ ghost: Bool) -> some View {
        HStack(spacing: 4) {
            Picker("", selection: part.kind) {
                Text(t("kv.kindText")).tag("text")
                Text(t("kv.kindFile")).tag("file")
            }
            .labelsHidden()
            .fixedSize()
            if part.wrappedValue.kind == "file" {
                FileButton(path: part.wrappedValue.path, pick: { await pick($0) }) { part.wrappedValue.path = $0 }
            } else {
                VarField(text: part.value, placeholder: ghost ? t("kv.value") : "", font: fonts.codeNSFont)
            }
        }
    }

    /// Validace jen jako varování (proměnné mimo řetězce bere formatter jako hodnotu).
    private var jsonWarning: String? {
        guard !requestBody.raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let err = JSONFormatter.validate(requestBody.raw) else { return nil }
        return errorText(err)
    }

    private func format() {
        do { requestBody.raw = try JSONFormatter.format(requestBody.raw) } catch { model.toasts.show(errorText(error), isError: true) }
    }

    /// Soubor z dialogu (`nil` URL) nebo přetažený → cesta relativní k projektu, mimo něj absolutní.
    private func pick(_ dropped: URL?) async -> String? {
        do {
            let project = try await model.projects.project(projectID)
            guard let url = dropped ?? {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                panel.directoryURL = project.root
                return panel.runModal() == .OK ? panel.url : nil
            }() else { return nil }
            return project.fileRef(url.path)
        } catch {
            model.toasts.show(errorText(error), isError: true)
            return nil
        }
    }
}

/// Tlačítko s vybranou cestou (nebo „Vybrat soubor…“); přijímá i přetažený soubor.
private struct FileButton: View {
    @Environment(\.appFonts) private var fonts
    let path: String
    let pick: (URL?) async -> String?
    let set: (String) -> Void

    init(path: String, pick: @escaping (URL?) async -> String?, set: @escaping (String) -> Void) {
        self.path = path
        self.pick = pick
        self.set = set
    }

    var body: some View {
        Button { choose(nil) } label: {
            Text(path.isEmpty ? t("kv.pickFile") : path)
                .font(path.isEmpty ? fonts.ui : fonts.code)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .help(path)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.isFileURL else { return false }
            choose(url)
            return true
        }
    }

    private func choose(_ url: URL?) {
        Task { if let p = await pick(url) { set(p) } }
    }
}
