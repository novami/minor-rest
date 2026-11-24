import Foundation
import Observation
import SwiftUI

/// Platné proměnné aktivního tabu (nebo projektu bez tabu) pro `VarField` a „oko“ a runtime proměnné
/// per projekt (jen v paměti, plní je `extract`). Tajné hodnoty se tu nečtou z Keychain – UI je jen maskuje.
@MainActor @Observable
final class VarsStore {
    /// Co ovlivňuje výsledek; změna = přepočet.
    struct Key: Equatable {
        var projectID: String
        var tabID: String?
        var rel: String?
        var requestVars: [Var]
        var environment: EnvironmentConfig?
        var globals: [Var]
        var runtime: [Var]
        var revision: Int
    }

    private(set) var context: VarContext?
    private(set) var runtime: [String: [Var]] = [:]
    /// Zvýší se při změně konfigurace projektu/složky (disk, nastavení).
    private(set) var revision = 0

    @ObservationIgnored private let projects: ProjectsStore
    @ObservationIgnored private let tabs: TabsStore
    @ObservationIgnored private let environments: EnvironmentsStore

    init(projects: ProjectsStore, tabs: TabsStore, environments: EnvironmentsStore) {
        self.projects = projects
        self.tabs = tabs
        self.environments = environments
    }

    var key: Key? {
        guard projects.active != nil else { return nil }
        let pid = projects.activeID
        let tab = tabs.active
        return Key(
            projectID: pid, tabID: tab?.id, rel: tab?.rel, requestVars: tab?.draft.vars ?? [],
            environment: environments.active(pid), globals: environments.globals,
            runtime: runtime[pid] ?? [], revision: revision)
    }

    func invalidate() { revision += 1 }

    /// Přepočet pro aktuální `key` (čtení složek mimo hlavní vlákno).
    func refresh() async {
        guard let key else {
            context = nil
            return
        }
        guard let project = try? await projects.project(key.projectID) else { return }
        let rel = key.rel
        let folders = await Task.detached { rel.flatMap { try? project.folderChain($0) } ?? [] }.value
        guard self.key == key else { return }  // mezitím se změnil vstup
        let input = PrepareInput(
            request: Request(vars: key.requestVars), project: project.config,
            folders: folders, runtime: key.runtime,
            environment: key.environment?.vars ?? [], globals: key.globals)
        context = VarContext(projectID: key.projectID, tabID: key.tabID, infos: Prepare.explain(input))
    }

    func runtimeVars(_ projectID: String) -> [Var] { runtime[projectID] ?? [] }

    /// Nastaví runtime proměnnou (extract v F8).
    func setRuntime(_ projectID: String, _ name: String, _ value: String) {
        var list = runtime[projectID] ?? []
        list.removeAll { $0.name == name }
        list.append(Var(name: name, value: value))
        runtime[projectID] = list.sorted { $0.name < $1.name }
    }

    func deleteRuntime(_ projectID: String, _ name: String) {
        runtime[projectID]?.removeAll { $0.name == name }
    }

    func projectClosed(_ projectID: String) { runtime[projectID] = nil }
}

/// Platné proměnné pro zvýraznění a hover ve `VarField`.
struct VarContext: Equatable {
    let projectID: String
    let tabID: String?
    let infos: [VarInfo]
    let byName: [String: VarInfo]

    init(projectID: String, tabID: String?, infos: [VarInfo]) {
        self.projectID = projectID
        self.tabID = tabID
        self.infos = infos
        byName = Dictionary(infos.map { ($0.name, $0) }, uniquingKeysWith: { arg, _ in arg })
    }

    func isKnown(_ name: String) -> Bool {
        name.hasPrefix("$") ? Resolver.dynamicNames.contains(name) : byName[name] != nil
    }

    /// Návrhy názvů pro `{{` (proměnné, pak dynamické) začínající `prefix`; bez kontextu jen dynamické.
    static func completions(_ context: VarContext?, _ prefix: String) -> [String] {
        let all = (context?.infos.map(\.name) ?? []) + Resolver.dynamicNames
        guard !prefix.isEmpty else { return all }
        return all.filter { $0.lowercased().hasPrefix(prefix.lowercased()) && $0 != prefix }
    }
}

extension EnvironmentValues {
    /// Kontext proměnných pro `VarField` (nastavuje editor requestu); `nil` = jen syntaktické zvýraznění.
    @Entry var varContext: VarContext?
}
