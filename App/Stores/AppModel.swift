import Observation
import SwiftUI

/// Sdílený stav okna (aplikace má jedno hlavní okno, menu volá akce přímo).
@MainActor @Observable
final class AppModel {
    let toasts = ToastCenter()
    let workspace = WorkspaceStore()
    let projects: ProjectsStore
    let tree: TreeStore
    let tabs: TabsStore
    let runs: RunStore

    init() {
        projects = ProjectsStore(workspace: workspace, toasts: toasts)
        tree = TreeStore(workspace: workspace, projects: projects, toasts: toasts)
        tabs = TabsStore(workspace: workspace, projects: projects, toasts: toasts)
        runs = RunStore(projects: projects)
        projects.onDiskChange = { [tree, tabs] id, rels in
            tree.diskChanged(id)
            Task { await tabs.changedOnDisk(id, rels) }
        }
        tree.onLoaded = { [tabs] id, root in await tabs.treeLoaded(id, root) }
        tree.onOpen = { [tabs] rel in await tabs.open(rel) }
        tabs.onSaved = { [tree] in await tree.reload() }
        tabs.treeRoot = { [tree] in tree.root }
    }

    /// Viditelnost sidebaru (uložená ve workspace).
    var columnVisibility: NavigationSplitViewVisibility {
        get { workspace.ws.sidebarHidden ? .detailOnly : .all }
        set { workspace.update { $0.sidebarHidden = newValue == .detailOnly } }
    }

    func toggleSidebar() {
        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
    }

    /// Odeslání aktivního tabu (⌘↩, tlačítko Odeslat).
    func send() {
        guard let tab = tabs.active else { return }
        Task { await runs.send(tab) }
    }

    /// Zrušení běhu aktivního tabu (⌘.).
    func cancelRun() {
        guard let tab = tabs.active else { return }
        Task { await runs.cancel(tab.id) }
    }

    /// Zavře projekt; neuložené taby projektu se nejdřív nabídnou k uložení.
    func closeProject(_ id: String) async {
        guard let p = projects.list.first(where: { $0.id == id }),
              await tabs.confirmCloseProject(id, name: p.name) else { return }
        await projects.close(id)
    }

    /// Dočasně pro akce menu, které ještě nejsou implementované.
    func notImplemented(_ labelKey: String) {
        toasts.show(t("toast.notImplemented", ["action": t(labelKey)]))
    }
}

@MainActor @Observable
final class ToastCenter {
    struct Toast: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    private(set) var items: [Toast] = []

    func show(_ text: String, isError: Bool = false, seconds: Double = 3) {
        let toast = Toast(text: text, isError: isError)
        items.append(toast)
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            items.removeAll { $0.id == toast.id }
        }
    }
}
