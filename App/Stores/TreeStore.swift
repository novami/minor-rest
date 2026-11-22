import AppKit
import MinorRESTCore
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

    @ObservationIgnored private let workspace: WorkspaceStore
    @ObservationIgnored private let projects: ProjectsStore
    @ObservationIgnored private let toasts: ToastCenter

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
        }
        projectID = id
        guard !id.isEmpty, let project = try? await projects.project(id) else {
            root = nil
            version += 1
            return
        }
        do {
            root = try project.loadTree()
        } catch {
            root = nil
            toasts.show(errorText(error), isError: true, seconds: 5)
        }
        version += 1
    }

    func reload() async { await load(projectID) }

    func setExpanded(_ rel: String, _ on: Bool) {
        guard !projectID.isEmpty else { return }
        editExpanded { list in
            if on { if !list.contains(rel) { list.append(rel) } } else { list.removeAll { $0 == rel } }
        }
    }

    func node(_ rel: String) -> TreeNode? {
        guard let root else { return nil }
        if rel.isEmpty { return root }
        func find(_ n: TreeNode) -> TreeNode? {
            if n.rel == rel { return n }
            for c in n.children where c.kind == .folder || c.rel == rel {
                if let hit = find(c) { return hit }
            }
            return nil
        }
        return find(root)
    }

    /// Cílová složka pro nový uzel: složka sama, u requestu jeho složka, jinak kořen.
    func targetFolder(for rel: String?) -> String {
        guard let rel, let n = node(rel) else { return "" }
        return n.kind == .folder ? n.rel : Self.parent(n.rel)
    }

    // MARK: - Operace

    func createRequest(near rel: String?) async {
        await create(near: rel) { try $0.createRequest(parent: $1, name: t("tree.newRequestName")) }
    }

    func createFolder(near rel: String?) async {
        await create(near: rel) { try $0.createFolder(parent: $1, name: t("tree.newFolderName")) }
    }

    func rename(_ rel: String, to name: String) async {
        guard let old = node(rel), old.name != name.nfc else { return }
        await perform { project in
            let n = try project.rename(rel, to: name)
            if old.kind == .folder { self.replaceExpandedPrefix(rel, with: n.rel) }
            if self.selection == rel { self.selection = n.rel }
        }
    }

    func duplicate(_ rel: String?) async {
        guard let rel, !rel.isEmpty else { return }
        await perform { project in
            let n = try project.duplicate(rel, copySuffix: t("tree.copySuffix"))
            self.selection = n.rel
        }
    }

    /// Smaže po potvrzení (`NSAlert`) do Koše.
    func delete(_ rel: String?) async {
        guard let rel, !rel.isEmpty, let n = node(rel) else { return }
        let alert = NSAlert()
        alert.messageText = t("tree.deleteTitle")
        alert.informativeText = t(n.kind == .folder ? "tree.deleteFolderMessage" : "tree.deleteRequestMessage",
                                  ["name": n.name])
        alert.addButton(withTitle: t("tree.delete")).hasDestructiveAction = true
        alert.addButton(withTitle: t("common.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        await perform { project in
            try project.delete(rel)
            self.replaceExpandedPrefix(rel, with: nil)
            if let s = self.selection, s == rel || s.hasPrefix(rel + "/") { self.selection = nil }
        }
    }

    func reveal(_ rel: String?) async {
        guard let project = try? await projects.project(projectID),
              let url = try? project.absoluteURL(rel ?? "") else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Pomocné

    private func create(near rel: String?, _ make: (Project, String) throws -> TreeNode) async {
        let parent = targetFolder(for: rel ?? selection)
        var created: String?
        await perform { project in
            let n = try make(project, parent)
            if !parent.isEmpty { self.setExpanded(parent, true) }
            self.selection = n.rel
            created = n.rel
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
            list = list.compactMap { p in
                guard p == rel || p.hasPrefix(rel + "/") else { return p }
                return newRel.map { $0 + p.dropFirst(rel.count) }
            }
        }
    }

    private static func parent(_ rel: String) -> String {
        rel.lastIndex(of: "/").map { String(rel[..<$0]) } ?? ""
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
