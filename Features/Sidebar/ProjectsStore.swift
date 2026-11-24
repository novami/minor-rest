import AppKit
import Observation

/// Otevřené projekty a aktivní projekt; seznam cest a aktivní projekt se zrcadlí do workspace.
@MainActor @Observable
final class ProjectsStore {
    private(set) var list: [ProjectInfo] = []
    private(set) var restored = false

    @ObservationIgnored let registry = ProjectRegistry()
    @ObservationIgnored private let workspace: WorkspaceStore
    @ObservationIgnored private let toasts: ToastCenter
    @ObservationIgnored private var watcher: ProjectWatcher?
    @ObservationIgnored private var watched: Set<String> = []
    /// Změna souborů projektu na disku (volá se na hlavním vlákně).
    @ObservationIgnored var onDiskChange: ((String, [String]?) -> Void)?

    init(workspace: WorkspaceStore, toasts: ToastCenter) {
        self.workspace = workspace
        self.toasts = toasts
        watcher = ProjectWatcher { [weak self] id, rels in
            Task { @MainActor in await self?.diskChanged(id, rels) }
        }
    }

    var activeID: String { workspace.ws.activeProject }
    var active: ProjectInfo? { list.first { $0.id == activeID } }

    /// Znovu otevře projekty z workspace; nečitelné vynechá (zapíše do logu).
    func restore() async {
        for path in workspace.ws.projects {
            do {
                try await registry.open(URL(fileURLWithPath: path))
            } catch {
                AppLog.app.error(
                    "projekt \(path, privacy: .public) nelze otevřít: \(error.localizedDescription, privacy: .public)")
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

    /// Přidá existující adresář projektu (např. právě naimportovaný) a aktivuje ho.
    func adopt(_ dir: URL) async -> Bool {
        do {
            let project = try await registry.open(dir)
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
        watcher?.remove(id: id)
        watched.remove(id)
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

    /// Znovu načte seznam (např. po změně názvu projektu).
    func reload() async { await sync(activate: nil) }

    /// Načte seznam z registru, zapíše cesty do workspace; neplatný aktivní projekt nahradí prvním.
    private func sync(activate id: String?) async {
        list = await registry.list()
        for info in list where !watched.contains(info.id) {
            watcher?.add(id: info.id, root: URL(fileURLWithPath: info.path))
            watched.insert(info.id)
        }
        let paths = await registry.paths()
        workspace.update { ws in
            ws.projects = paths
            if let id { ws.activeProject = id }
            if !list.contains(where: { $0.id == ws.activeProject }) { ws.activeProject = list.first?.id ?? "" }
        }
    }

    /// Změna `minorrest.yaml` (nebo neznámý rozsah) → znovu načíst konfiguraci a seznam; pak strom.
    private func diskChanged(_ id: String, _ rels: [String]?) async {
        guard let project = try? await registry.project(id) else { return }
        if rels?.contains(ProjectFormat.projectFile) ?? true {
            do {
                try project.reloadConfig()
            } catch {
                let reason = error.localizedDescription
                AppLog.app.error(
                    "konfigurace projektu \(id, privacy: .public) nelze načíst: \(reason, privacy: .public)")
            }
            list = await registry.list()
        }
        onDiskChange?(id, rels)
    }
}
