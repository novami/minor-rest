import SwiftUI
import UniformTypeIdentifiers

/// Průvodce importem OpenAPI / Swagger (kap. 7): zdroj → náhled → cíl a seskupení → Import.
struct ImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: ImportSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("import.title")).font(.headline)
            if session.step == .source { sourceStep } else { previewStep }
            if let error = session.error {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }
            buttons
        }
        .padding(20)
        .frame(width: 520)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.isFileURL }) else { return false }
            Task { await session.load(url) }
            return true
        }
    }

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("import.sourceHint")).foregroundStyle(.secondary)
            Button(t("import.chooseFile"), action: chooseFile)
            HStack {
                TextField(t("import.urlPlaceholder"), text: $session.urlText)
                    .onSubmit { Task { await session.loadURLText() } }
                Button(t("import.load")) { Task { await session.loadURLText() } }
                    .disabled(session.urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text(t("import.dropHint")).font(.callout).foregroundStyle(.secondary)
        }
        .disabled(session.busy)
    }

    @ViewBuilder private var previewStep: some View {
        if let preview = session.preview {
            VStack(alignment: .leading, spacing: 12) {
                Text(preview.title).font(.title3)
                Text(
                    t(
                        "import.summary",
                        [
                            "requests": String(preview.requestCount), "folders": String(preview.folders.count),
                            "servers": String(preview.serverCount),
                        ])
                ).foregroundStyle(.secondary)
                List(preview.folders, id: \.name) { folder in
                    HStack {
                        Label(folder.name, systemImage: "folder")
                        Spacer()
                        Text(String(folder.count)).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 130)
                if !preview.warnings.isEmpty { warnings(preview.warnings) }
                options
            }
        }
    }

    private func warnings(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t("import.warnings")).font(.callout.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, text in
                        Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                            .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 70)
        }
    }

    private var options: some View {
        Form {
            Picker(t("import.grouping"), selection: $session.grouping) {
                Text(t("import.groupTag")).tag(ImportOptions.Grouping.tag)
                Text(t("import.groupPath")).tag(ImportOptions.Grouping.pathSegment)
            }
            .pickerStyle(.segmented)
            Picker(t("import.target"), selection: $session.target) {
                Text(t("import.targetNew")).tag(ImportSession.Target.newProject)
                Text(t("import.targetExisting", ["name": model.projects.active?.name ?? ""]))
                    .tag(ImportSession.Target.existing)
                    .disabled(model.projects.active == nil)
            }
            if session.target == .newProject {
                TextField(t("project.name"), text: $session.name)
                LabeledContent(t("project.location")) {
                    HStack {
                        Text(session.location.path(percentEncoded: false)).lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button(t("project.changeLocation"), action: pickLocation)
                    }
                }
            }
        }
        .disabled(session.busy)
    }

    private var buttons: some View {
        HStack {
            if session.busy { ProgressView().controlSize(.small) }
            Spacer()
            if session.step == .preview {
                Button(t("import.back")) {
                    session.step = .source
                    session.error = nil
                }
            }
            Button(t("common.cancel"), role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            if session.step == .preview {
                Button(t("import.run"), action: run)
                    .keyboardShortcut(.defaultAction)
                    .disabled(session.busy || (session.target == .newProject && blankName))
            }
        }
    }

    private var blankName: Bool { session.name.trimmingCharacters(in: .whitespaces).isEmpty }

    private func run() {
        Task {
            guard let count = await session.run(model) else { return }
            model.toasts.show(t("import.done", ["count": String(count)]))
            dismiss()
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["json", "yaml", "yml"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await session.load(url) }
    }

    private func pickLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = session.location
        if panel.runModal() == .OK, let url = panel.url { session.location = url }
    }
}
