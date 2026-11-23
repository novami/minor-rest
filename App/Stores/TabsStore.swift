import AppKit
import MinorRESTCore
import Observation

/// Otevřený request. Identita = ID requestu (přežije přejmenování a přesun), `rel` se dorovnává podle stromu.
struct RequestTab: Identifiable, Equatable {
    let id: String
    let projectID: String
    var rel: String
    var draft: Request
    /// Stav posledního načtení/uložení (porovnáním vzniká „neuloženo“).
    var saved: Request
    /// Vlastní text URL baru (např. rozepsané `?`), dokud odpovídá `draft`.
    var urlText: String?
    /// Poslední záložka editoru (jen v paměti).
    var section: RequestSection = .params

    var dirty: Bool { draft != saved }
}

enum RequestSection: String, CaseIterable {
    case params, body, headers
}

/// Taby per projekt; seznam a aktivní tab se ukládají do workspace.
@MainActor @Observable
final class TabsStore {
    private(set) var list: [RequestTab] = []
    /// Zvýšení = přesunout fokus do URL baru.
    private(set) var focusURLRequest = 0

    @ObservationIgnored private let workspace: WorkspaceStore
    @ObservationIgnored private let projects: ProjectsStore
    @ObservationIgnored private let toasts: ToastCenter
    @ObservationIgnored private var restored: Set<String> = []
    /// Po uložení se znovu načte strom (metoda a URL ve stromu).
    @ObservationIgnored var onSaved: (() async -> Void)?
    /// Aktuální strom projektu (názvy tabů, dorovnání `rel`).
    @ObservationIgnored var treeRoot: () -> TreeNode? = { nil }

    init(workspace: WorkspaceStore, projects: ProjectsStore, toasts: ToastCenter) {
        self.workspace = workspace
        self.projects = projects
        self.toasts = toasts
    }

    private var projectID: String { projects.activeID }

    var projectTabs: [RequestTab] { list.filter { $0.projectID == projectID } }

    var activeID: String { workspace.ws.activeTab[projectID] ?? "" }

    var active: RequestTab? { list.first { $0.id == activeID && $0.projectID == projectID } }

    var anyDirty: Bool { list.contains(where: \.dirty) }

    /// Název ze stromu (přejmenování), jinak načtený.
    func name(_ tab: RequestTab) -> String {
        (tab.projectID == projectID ? treeRoot()?.findRequest(id: tab.id)?.name : nil) ?? tab.draft.name
    }

    func activate(_ id: String) {
        let pid = projectID
        workspace.update { $0.activeTab[pid] = id }
    }

    /// Otevře request `rel` aktivního projektu (už otevřený jen aktivuje).
    func open(_ rel: String) async {
        guard let node = treeRoot()?.find(rel), node.kind == .request, !node.id.isEmpty, node.error.isEmpty else { return }
        if !list.contains(where: { $0.id == node.id && $0.projectID == projectID }) {
            guard let tab = await load(projectID, node.id, rel) else { return }
            list.append(tab)
        }
        activate(node.id)
        persist()
    }

    /// Úprava draftu aktivního tabu.
    func edit(_ change: (inout RequestTab) -> Void) {
        guard let i = list.firstIndex(where: { $0.id == activeID && $0.projectID == projectID }) else { return }
        change(&list[i])
    }

    func focusURL() {
        if active != nil { focusURLRequest += 1 }
    }

    // MARK: - Uložení a zavření

    @discardableResult
    func save(_ id: String? = nil) async -> Bool {
        guard let i = index(id ?? activeID) else { return false }
        let tab = list[i]
        do {
            let project = try await projects.project(tab.projectID)
            try project.saveRequest(tab.rel, tab.draft)
            if let j = index(tab.id, tab.projectID) { list[j].saved = tab.draft }
            await onSaved?()
            return true
        } catch {
            toasts.show(errorText(error), isError: true, seconds: 5)
            return false
        }
    }

    /// Zavře tab; neuložený se nejdřív zeptá Uložit / Zahodit / Zrušit.
    func close(_ id: String? = nil) async {
        guard let i = index(id ?? activeID) else {
            if id == nil { NSApp.keyWindow?.performClose(nil) }   // Cmd+W bez tabu zavře okno
            return
        }
        let tab = list[i]
        if tab.dirty {
            let alert = NSAlert()
            alert.messageText = t("tabs.unsavedTitle")
            alert.informativeText = t("tabs.unsavedMessage", ["name": name(tab)])
            alert.addButton(withTitle: t("tabs.save"))
            alert.addButton(withTitle: t("tabs.discard")).hasDestructiveAction = true
            alert.addButton(withTitle: t("common.cancel"))
            switch alert.runModal() {
            case .alertFirstButtonReturn: guard await save(tab.id) else { return }
            case .alertSecondButtonReturn: break
            default: return
            }
        }
        remove(tab.id)
    }

    // MARK: - Synchronizace se stromem

    /// Po načtení stromu: zahodí taby zavřených projektů, dorovná `rel` podle ID, zavře smazané čisté taby
    /// a jednou za běh obnoví taby projektu z workspace.
    func treeLoaded(_ pid: String, _ root: TreeNode?) async {
        let open = Set(projects.list.map(\.id))
        list.removeAll { !open.contains($0.projectID) }
        guard !pid.isEmpty, pid == projectID, let root else { return }
        list = list.compactMap { tab in
            guard tab.projectID == pid else { return tab }
            guard let n = root.findRequest(id: tab.id) else { return tab.dirty ? tab : nil }
            var t = tab
            t.rel = n.rel
            return t
        }
        if !restored.contains(pid) {
            restored.insert(pid)
            for id in workspace.ws.tabs[pid] ?? [] where !list.contains(where: { $0.id == id && $0.projectID == pid }) {
                guard let n = root.findRequest(id: id), n.error.isEmpty,
                      let tab = await load(pid, id, n.rel) else { continue }
                list.append(tab)
            }
        }
        let ids = projectTabs.map(\.id)
        if !ids.contains(activeID) { activate(ids.first ?? "") }
        persist()
    }

    // MARK: - Pomocné

    private func index(_ id: String, _ pid: String? = nil) -> Int? {
        let pid = pid ?? projectID
        return list.firstIndex { $0.id == id && $0.projectID == pid }
    }

    private func load(_ pid: String, _ id: String, _ rel: String) async -> RequestTab? {
        do {
            let r = try await projects.project(pid).loadRequest(rel)
            return RequestTab(id: id, projectID: pid, rel: rel, draft: r, saved: r)
        } catch {
            toasts.show(errorText(error), isError: true, seconds: 5)
            return nil
        }
    }

    private func remove(_ id: String) {
        let tabs = projectTabs
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        list.removeAll { $0.id == id && $0.projectID == projectID }
        if activeID == id {
            let next = i + 1 < tabs.count ? tabs[i + 1] : (i > 0 ? tabs[i - 1] : nil)
            activate(next?.id ?? "")
        }
        persist()
    }

    private func persist() {
        let pid = projectID
        guard !pid.isEmpty else { return }
        let ids = projectTabs.map(\.id)
        workspace.update { ws in
            ws.tabs[pid] = ids.isEmpty ? nil : ids
            if ws.activeTab[pid]?.isEmpty ?? false { ws.activeTab[pid] = nil }
        }
    }
}
