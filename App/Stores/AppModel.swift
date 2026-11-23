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

    init() {
        projects = ProjectsStore(workspace: workspace, toasts: toasts)
        tree = TreeStore(workspace: workspace, projects: projects, toasts: toasts)
        tabs = TabsStore(workspace: workspace, projects: projects, toasts: toasts)
        projects.onDiskChange = { [tree] id in tree.diskChanged(id) }
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
