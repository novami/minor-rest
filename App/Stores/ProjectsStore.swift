import AppKit
import MinorRESTCore
import Observation

/// Otevřené projekty a aktivní projekt; seznam cest a aktivní projekt se zrcadlí do workspace.
@MainActor @Observable
final class ProjectsStore {
    private(set) var list: [ProjectInfo] = []
    private(set) var restored = false

    @ObservationIgnored let registry = ProjectRegistry()
    @ObservationIgnored private let workspace: WorkspaceStore
    @ObservationIgnored private let toasts: ToastCenter

    init(workspace: WorkspaceStore, toasts: ToastCenter) {
        self.workspace = workspace
        self.toasts = toasts
    }

    var activeID: String { workspace.ws.activeProject }
    var active: ProjectInfo? { list.first { $0.id == activeID } }

    /// Znovu otevře projekty z workspace; nečitelné vynechá (zapíše do logu).
    func restore() async {
        for path in workspace.ws.projects {
            do {
                try await registry.open(URL(fileURLWithPath: path))
            } catch {
                log.error("projekt \(path, privacy: .public) nelze otevřít: \(String(describing: error))")
            }
        }
        await sync(activate: nil)
        restored = true
    }

    func activate(_ id: String) {
        workspace.update { $0.activeProject = id }
    }

    /// Založí projekt v podadresáři `parentDir` a aktivuje ho.
    func create(name: String, in parentDir: URL) async -> Bool {
        do {
            let project = try Project.create(name: name, in: parentDir)
            await registry.add(project)
            await sync(activate: project.info.id)
            return true
        } catch {
            toasts.show(errorText(error), isError: true, seconds: 5)
            return false
        }
    }

    /// Výběr adresáře; adresář bez projektu nabídne založit (název = název adresáře).
    func openDirectory() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = t("project.open").replacingOccurrences(of: "…", with: "")
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        do {
            let project: Project
            if Project.isProjectDir(dir) {
                project = try await registry.open(dir)
            } else {
                let alert = NSAlert()
                alert.messageText = t("project.initTitle")
                alert.informativeText = t("project.initMessage", ["name": dir.lastPathComponent])
                alert.addButton(withTitle: t("project.initCreate"))
                alert.addButton(withTitle: t("common.cancel"))
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                project = await registry.add(try Project.initProject(at: dir, name: dir.lastPathComponent))
            }
            await sync(activate: project.info.id)
        } catch {
            toasts.show(errorText(error), isError: true, seconds: 5)
        }
    }

    func close(_ id: String) async {
        try? await registry.close(id)
        workspace.update {
            $0.expanded[id] = nil
            $0.tabs[id] = nil
            $0.activeTab[id] = nil
        }
        await sync(activate: nil)
    }

    func project(_ id: String) async throws -> Project {
        try await registry.project(id)
    }

    /// Načte seznam z registru, zapíše cesty do workspace; neplatný aktivní projekt nahradí prvním.
    private func sync(activate id: String?) async {
        list = await registry.list()
        let paths = await registry.paths()
        workspace.update { ws in
            ws.projects = paths
            if let id { ws.activeProject = id }
            if !list.contains(where: { $0.id == ws.activeProject }) { ws.activeProject = list.first?.id ?? "" }
        }
    }
}
