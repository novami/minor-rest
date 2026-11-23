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
    /// Poslední záložka odpovědi (jen v paměti).
    var responseSection: ResponseSection = .body
    /// Novější verze z disku, zatímco tab má neuložené změny (banner Načíst z disku / Ponechat moje).
    var diskChanged: Request?

    var dirty: Bool { draft != saved }
}

enum RequestSection: String, CaseIterable {
    case params, body, headers, auth, vars, settings, docs
}

enum ResponseSection: String, CaseIterable {
    case body, headers, cookies, timing, sent, redirects, versions
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
    /// Hlavní okno (Cmd+W v jiném okně zavře to okno).
    @ObservationIgnored weak var mainWindow: NSWindow?
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
        return await save(list[i])
    }

    private func save(_ tab: RequestTab, reloadTree: Bool = true) async -> Bool {
        do {
            let project = try await projects.project(tab.projectID)
            try project.saveRequest(tab.rel, tab.draft)
            if let j = index(tab.id, tab.projectID) {
                list[j].saved = tab.draft
                list[j].diskChanged = nil
            }
            if reloadTree { await onSaved?() }
            return true
        } catch {
            toasts.show(errorText(error), isError: true, seconds: 5)
            return false
        }
    }

    /// Uloží neuložené taby (jednoho projektu, nebo všechny); `false`, když některé uložení selhalo.
    func saveAll(projectID pid: String? = nil) async -> Bool {
        var ok = true
        for tab in list where tab.dirty && (pid == nil || tab.projectID == pid) {
            ok = await save(tab, reloadTree: false) && ok
        }
        await onSaved?()
        return ok
    }

    /// Před zavřením projektu s neuloženými taby: Uložit vše / Zahodit / Zrušit. `true` = pokračovat.
    func confirmCloseProject(_ pid: String, name: String) async -> Bool {
        guard list.contains(where: { $0.projectID == pid && $0.dirty }) else { return true }
        switch ask(t("tabs.unsavedTitle"), t("tabs.unsavedProject", ["name": name]),
                   save: t("tabs.saveAll"), discard: t("tabs.discard")) {
        case .alertFirstButtonReturn: guard await saveAll(projectID: pid) else { return false }
        case .alertSecondButtonReturn: break
        default: return false
        }
        list.removeAll { $0.projectID == pid }
        return true
    }

    /// Dotaz před ukončením: `nil` = zrušit, `true` = nejdřív uložit vše, `false` = ukončit bez uložení.
    func askBeforeQuit() -> Bool? {
        guard anyDirty else { return false }
        switch ask(t("quit.title"), t("quit.message"), save: t("tabs.save"), discard: t("quit.dontSave")) {
        case .alertFirstButtonReturn: return true
        case .alertSecondButtonReturn: return false
        default: return nil
        }
    }

    private func ask(_ title: String, _ message: String, save: String, discard: String) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: save)
        alert.addButton(withTitle: discard).hasDestructiveAction = true
        alert.addButton(withTitle: t("common.cancel"))
        return alert.runModal()
    }

    /// Zavře tab; neuložený se nejdřív zeptá Uložit / Zahodit / Zrušit.
    func close(_ id: String? = nil) async {
        if id == nil, let w = NSApp.keyWindow, w !== mainWindow {   // Cmd+W v jiném okně (Nastavení)
            w.performClose(nil)
            return
        }
        guard let i = index(id ?? activeID) else {
            if id == nil { NSApp.terminate(nil) }   // Cmd+W bez tabu zavře okno = ukončí aplikaci
            return
        }
        let tab = list[i]
        if tab.dirty {
            switch ask(t("tabs.unsavedTitle"), t("tabs.unsavedMessage", ["name": name(tab)]),
                       save: t("tabs.save"), discard: t("tabs.discard")) {
            case .alertFirstButtonReturn: guard await save(tab.id) else { return }
            case .alertSecondButtonReturn: break
            default: return
            }
        }
        remove(tab.id)
    }

    // MARK: - Změna na disku

    /// Soubory projektu se změnily zvenku (`rels == nil` = neznámý rozsah): čistý tab se tiše znovu načte,
    /// neuložený dostane banner. Smazaný/přesunutý request řeší synchronizace se stromem.
    func changedOnDisk(_ pid: String, _ rels: [String]?) async {
        let changed = rels.map(Set.init)
        for tab in list where tab.projectID == pid && (changed?.contains(tab.rel) ?? true) {
            guard let r = try? await projects.project(pid).loadRequest(tab.rel),
                  let i = index(tab.id, pid) else { continue }
            if r == list[i].saved {
                list[i].diskChanged = nil
            } else if list[i].dirty {
                list[i].diskChanged = r
            } else {
                list[i].draft = r
                list[i].saved = r
                list[i].urlText = nil
            }
        }
    }

    func reloadFromDisk(_ id: String) {
        guard let i = index(id), let r = list[i].diskChanged else { return }
        list[i].draft = r
        list[i].saved = r
        list[i].urlText = nil
        list[i].diskChanged = nil
    }

    /// Ponechá lokální úpravy; verze z disku se stane výchozí, takže tab zůstane neuložený vůči ní.
    func keepMine(_ id: String) {
        guard let i = index(id), let r = list[i].diskChanged else { return }
        list[i].saved = r
        list[i].diskChanged = nil
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
            var tab = RequestTab(id: id, projectID: pid, rel: rel, draft: r, saved: r)
            if let s = DebugTools.initialSection.flatMap(RequestSection.init) { tab.section = s }
            return tab
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
