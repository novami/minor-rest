import AppKit
import Observation

/// Strom aktivního projektu: načtení, výběr, rozbalení (ve workspace) a operace nad uzly.
@MainActor @Observable
final class TreeStore {
    private(set) var root: TreeNode?
    private(set) var projectID = ""
    /// Zvyšuje se při každém načtení stromu (signál pro `TreeOutlineView`).
    private(set) var version = 0
    var selection: String?
    /// Uzel, jehož název má view po načtení otevřít k editaci.
    var pendingEdit: String?
    /// Filtr stromu (prázdný = celý strom); během filtru je vše rozbalené a DnD vypnutý.
    var query = ""
    /// Zvýšení = přesunout fokus z pole hledání do stromu.
    private(set) var focusRequest = 0

    var filtering: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    /// Strom k zobrazení (po filtru).
    var visibleRoot: TreeNode? { root.map { filtering ? $0.filtered(query) : $0 } }

    @ObservationIgnored private let workspace: WorkspaceStore
    @ObservationIgnored private let projects: ProjectsStore
    @ObservationIgnored private let toasts: ToastCenter
    /// Po každém načtení stromu (taby dorovnají `rel`).
    @ObservationIgnored var onLoaded: ((String, TreeNode?) async -> Void)?
    /// Otevření requestu v tabu.
    @ObservationIgnored var onOpen: ((String) async -> Void)?

    init(workspace: WorkspaceStore, projects: ProjectsStore, toasts: ToastCenter) {
        self.workspace = workspace
        self.projects = projects
        self.toasts = toasts
    }

    var expanded: Set<String> { Set(workspace.ws.expanded[projectID] ?? []) }

    /// Načte strom projektu `id` (prázdné = žádný projekt); při změně projektu zruší výběr.
    func load(_ id: String) async {
        if id != projectID {
            selection = nil
            pendingEdit = nil
            query = ""
        }
        projectID = id
        guard !id.isEmpty, let project = try? await projects.project(id) else {
            root = nil
            version += 1
            await onLoaded?(id, nil)
            return
        }
        do {
            root = try project.loadTree()
        } catch {
            root = nil
            toasts.show(errorText(error), isError: true, seconds: 5)
        }
        version += 1
        await onLoaded?(id, root)
    }

    func reload() async { await load(projectID) }

    /// Probíhá inline editace názvu (reload by zahodil field editor a přejmenoval na rozepsaný text).
    @ObservationIgnored var editing = false {
        didSet { if !editing && reloadPending { reloadPending = false; Task { await reload() } } }
    }
    @ObservationIgnored private var reloadPending = false

    /// Změna na disku (watcher); během editace se reload odloží na její konec.
    func diskChanged(_ id: String) {
        guard id == projectID else { return }
        if editing { reloadPending = true } else { Task { await reload() } }
    }

    func setExpanded(_ rel: String, _ on: Bool) {
        guard !projectID.isEmpty else { return }
        editExpanded { list in
            if on { if !list.contains(rel) { list.append(rel) } } else { list.removeAll { $0 == rel } }
        }
    }

    func node(_ rel: String) -> TreeNode? { root?.find(rel) }

    /// Fokus do stromu (z pole hledání); bez viditelného výběru vybere první řádek.
    func focusTree() {
        if let val = visibleRoot, selection.flatMap(val.find) == nil { selection = val.children.first?.rel }
        focusRequest += 1
    }

    /// Cílová složka pro nový uzel: složka sama, u requestu jeho složka, jinak kořen.
    func targetFolder(for rel: String?) -> String {
        guard let rel, let num = node(rel) else { return "" }
        return num.kind == .folder ? num.rel : TreeNode.parent(of: num.rel)
    }

    // MARK: - Operace

    /// Otevře request v tabu (dvojklik / Enter).
    func open(_ rel: String?) async {
        guard let rel, node(rel)?.kind == .request else { return }
        await onOpen?(rel)
    }

    /// Nový request se hned otevře v tabu, název zůstane v inline editaci ve stromu.
    func createRequest(near rel: String?) async {
        await create(near: rel) { try $0.createRequest(parent: $1, name: t("tree.newRequestName")) }
        if let created = pendingEdit { await onOpen?(created) }
    }

    func createFolder(near rel: String?) async {
        await create(near: rel) { try $0.createFolder(parent: $1, name: t("tree.newFolderName")) }
    }

    func rename(_ rel: String, to name: String) async {
        guard let old = node(rel), old.name != name.nfc else { return }
        await perform { project in
            let num = try project.rename(rel, to: name)
            if old.kind == .folder { self.replaceExpandedPrefix(rel, with: num.rel) }
            if self.selection == rel { self.selection = num.rel }
        }
    }

    /// Přesun do složky `parent` na `index` mezi sourozenci stejného druhu.
    func move(_ rel: String, to parent: String, index: Int) async {
        guard let old = node(rel) else { return }
        await perform { project in
            let num = try project.move(rel, to: parent, index: index)
            if old.kind == .folder { self.replaceExpandedPrefix(rel, with: num.rel) }
            if !parent.isEmpty { self.setExpanded(parent, true) }
            if let str = self.selection, str == rel || str.hasPrefix(rel + "/") {
                self.selection = num.rel + str.dropFirst(rel.count)
            }
        }
    }

    func duplicate(_ rel: String?) async {
        guard let rel, !rel.isEmpty else { return }
        await perform { project in
            let num = try project.duplicate(rel, copySuffix: t("tree.copySuffix"))
            self.selection = num.rel
        }
    }

    /// Smaže po potvrzení (`NSAlert`) do Koše.
    func delete(_ rel: String?) async {
        guard let rel, !rel.isEmpty, let num = node(rel) else { return }
        let alert = NSAlert()
        alert.messageText = t("tree.deleteTitle")
        alert.informativeText = t(num.kind == .folder ? "tree.deleteFolderMessage" : "tree.deleteRequestMessage",
                                  ["name": num.name])
        alert.addButton(withTitle: t("tree.delete")).hasDestructiveAction = true
        alert.addButton(withTitle: t("common.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        await perform { project in
            try project.delete(rel)
            self.replaceExpandedPrefix(rel, with: nil)
            if let str = self.selection, str == rel || str.hasPrefix(rel + "/") { self.selection = nil }
        }
    }

    /// Nastavení složky (napojeno v `AppModel`).
    var onSettings: ((String, String) -> Void)?
    var onCopyCurl: ((String) -> Void)?

    func openSettings(_ rel: String) {
        if let node = root?.find(rel) { onSettings?(rel, node.name) }
    }

    func reveal(_ rel: String?) async {
        guard let project = try? await projects.project(projectID),
              let url = try? project.absoluteURL(rel ?? "") else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Pomocné

    private func create(near rel: String?, _ make: (Project, String) throws -> TreeNode) async {
        let parent = targetFolder(for: rel ?? selection)
        query = ""
        var created: String?
        await perform { project in
            let num = try make(project, parent)
            if !parent.isEmpty { self.setExpanded(parent, true) }
            self.selection = num.rel
            created = num.rel
        }
        pendingEdit = created
    }

    /// Provede operaci nad aktivním projektem, chybu ukáže toastem a strom znovu načte.
    private func perform(_ op: (Project) throws -> Void) async {
        guard !projectID.isEmpty else { return }
        do {
            try op(try await projects.project(projectID))
        } catch {
            toasts.show(errorText(error), isError: true, seconds: 5)
        }
        await reload()
    }

    /// Po přejmenování/smazání složky přepíše (nil = odstraní) rozbalené cesty pod ní.
    private func replaceExpandedPrefix(_ rel: String, with newRel: String?) {
        editExpanded { list in
            list = list.compactMap { par in
                guard par == rel || par.hasPrefix(rel + "/") else { return par }
                return newRel.map { $0 + par.dropFirst(rel.count) }
            }
        }
    }

    private func editExpanded(_ change: (inout [String]) -> Void) {
        let id = projectID
        workspace.update { ws in
            var list = ws.expanded[id] ?? []
            change(&list)
            ws.expanded[id] = list.isEmpty ? nil : list
        }
    }
}
