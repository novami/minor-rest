import Foundation
import MinorRESTCore
import Observation

/// Prostředí projektů, aktivní prostředí (ve workspace) a globální proměnné. Seznamy jsou bez hodnot
/// tajných proměnných; ty se čtou z Keychain až při odeslání (mimo hlavní vlákno – macOS se může ptát).
@MainActor @Observable
final class EnvironmentsStore {
    private(set) var lists: [String: [EnvironmentConfig]] = [:]
    private(set) var globals: [Var] = []

    @ObservationIgnored let secrets: SecretStore = Secrets()
    @ObservationIgnored private let workspace: WorkspaceStore
    @ObservationIgnored private let projects: ProjectsStore
    @ObservationIgnored private let toasts: ToastCenter

    init(workspace: WorkspaceStore, projects: ProjectsStore, toasts: ToastCenter) {
        self.workspace = workspace
        self.projects = projects
        self.toasts = toasts
        loadGlobals()
    }

    func environments(_ projectID: String) -> [EnvironmentConfig] { lists[projectID] ?? [] }

    /// Aktivní prostředí; ID, které v seznamu není (smazané soubor), = žádné.
    func active(_ projectID: String) -> EnvironmentConfig? {
        guard let id = workspace.ws.activeEnvironment[projectID] else { return nil }
        return environments(projectID).first { $0.id == id }
    }

    func select(_ projectID: String, _ envID: String?) {
        workspace.update { $0.activeEnvironment[projectID] = envID }
    }

    func load(_ projectID: String) async {
        guard let project = try? await projects.project(projectID) else { return }
        do {
            lists[projectID] = try await Task.detached { try project.listEnvironments() }.value
        } catch {
            toasts.show(errorText(error), isError: true)
        }
    }

    func loadGlobals() {
        do {
            globals = try Globals.load(from: workspace.directory)
        } catch {
            log.error("globals.yaml nelze načíst: \(String(describing: error))")
        }
    }

    /// Soubor v `environments/` změněný zvenku (nebo neznámý rozsah) → znovu načíst seznam.
    func diskChanged(_ projectID: String, _ rels: [String]?) async {
        let prefix = ProjectFormat.environmentDir + "/"
        guard rels?.contains(where: { $0.hasPrefix(prefix) }) ?? true else { return }
        await load(projectID)
    }

    func projectClosed(_ projectID: String) {
        lists[projectID] = nil
        workspace.update { $0.activeEnvironment[projectID] = nil }
    }

    /// Data pro okno Prostředí: prostředí, proměnné projektu a globální, tajné hodnoty doplněné z Keychain.
    struct Editable: Sendable {
        var environments: [EnvironmentConfig]
        var projectVars: [Var]
        var globals: [Var]
        var readOnly: Bool
    }

    func loadEditable(_ projectID: String) async throws -> Editable {
        let project = try await projects.project(projectID)
        let secrets = secrets, dir = workspace.directory
        return try await Task.detached {
            let envs = try project.listEnvironments().map { e in
                var e = e
                e.vars = try secrets.fill(e.vars, account: project.secretAccount(envID: e.id))
                return e
            }
            let globals = try secrets.fill(try Globals.load(from: dir), account: Secrets.globalAccount)
            return Editable(environments: envs, projectVars: project.config.vars, globals: globals,
                            readOnly: project.info.readOnly)
        }.value
    }

    /// Uloží změny: smazaná prostředí, změněná/nová prostředí, proměnné projektu a globální.
    func saveEditable(_ projectID: String, original: Editable, edited: Editable) async throws {
        let project = try await projects.project(projectID)
        let secrets = secrets, dir = workspace.directory
        try await Task.detached {
            let kept = Set(edited.environments.map(\.id))
            for e in original.environments where !kept.contains(e.id) {
                try project.deleteEnvironment(id: e.id, secrets: secrets)
            }
            for e in edited.environments where original.environments.first(where: { $0.id == e.id }) != e {
                _ = try project.saveEnvironment(e, secrets: secrets)
            }
            if edited.projectVars != original.projectVars {
                var cfg = project.config
                cfg.vars = edited.projectVars
                try project.saveConfig(cfg)
            }
            if edited.globals != original.globals {
                try Globals.save(edited.globals, to: dir, secrets: secrets)
            }
        }.value
        await load(projectID)
        loadGlobals()
    }

    /// Proměnné aktivního prostředí a globální s hodnotami z Keychain (pro `Prepare`).
    func varsForSend(_ projectID: String) async throws -> (environment: [Var], globals: [Var]) {
        let env = active(projectID), globals = globals, secrets = secrets
        let project = try await projects.project(projectID)
        return try await Task.detached {
            let ev = try env.map { try secrets.fill($0.vars, account: project.secretAccount(envID: $0.id)) } ?? []
            return (ev, try secrets.fill(globals, account: Secrets.globalAccount))
        }.value
    }
}
