import MinorRESTCore
import SwiftUI

/// Přepínač projektů v toolbaru: otevřené projekty, nový, otevřít adresář, zavřít.
struct ProjectSwitcher: View {
    @Environment(AppModel.self) private var model
    @State private var showNew = false

    var body: some View {
        let projects = model.projects
        Menu {
            ForEach(projects.list, id: \.id) { p in
                Button {
                    projects.activate(p.id)
                } label: {
                    if p.id == projects.activeID {
                        Label(title(p), systemImage: "checkmark")
                    } else {
                        Text(title(p))
                    }
                }
            }
            if !projects.list.isEmpty { Divider() }
            Button(t("project.new")) { showNew = true }
            Button(t("project.open")) { Task { await projects.openDirectory() } }
            Divider()
            Button(t("project.close")) {
                Task { await projects.close(projects.activeID) }
            }
            .disabled(projects.active == nil)
        } label: {
            Text(projects.active.map(title) ?? t("project.none"))
        }
        .help(projects.active?.path ?? "")
        .sheet(isPresented: $showNew) {
            NewProjectSheet()
        }
    }

    private func title(_ p: ProjectInfo) -> String {
        p.readOnly ? "\(p.name) (\(t("project.readOnly")))" : p.name
    }
}

/// Založení projektu: název a umístění (výchozí `~/Documents/MinorREST`).
struct NewProjectSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var location = Workspace.defaultProjectsDirectory
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("project.newTitle")).font(.headline)
            Form {
                TextField(t("project.name"), text: $name)
                LabeledContent(t("project.location")) {
                    HStack {
                        Text(location.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .help(location.path(percentEncoded: false))
                        Button(t("project.changeLocation"), action: pickLocation)
                    }
                }
            }
            HStack {
                Spacer()
                Button(t("common.cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(t("common.create"), action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func pickLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = location
        if panel.runModal() == .OK, let url = panel.url { location = url }
    }

    private func create() {
        busy = true
        Task {
            if await model.projects.create(name: name, in: location) { dismiss() }
            busy = false
        }
    }
}
