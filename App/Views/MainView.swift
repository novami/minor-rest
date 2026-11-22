import SwiftUI

/// Rozvržení hlavního okna: sidebar | request / odpověď. Šířku sidebaru a rámec okna ukládá AppKit
/// (autosave `NSSplitView`/`NSWindow`), výšku odpovědi workspace.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var scale: CGFloat = 2

    var body: some View {
        @Bindable var model = model
        let fonts = AppFonts.forScale(scale)
        let responseHeight = Binding(
            get: { CGFloat(model.workspace.ws.responseHeight) },
            set: { h in model.workspace.update { $0.responseHeight = Int(h) } })
        NavigationSplitView(columnVisibility: $model.columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 260, max: 600)
        } detail: {
            ResponseSplit(height: responseHeight) {
                EmptyState(title: t("request.empty"), hint: t("request.emptyHint"))
            } bottom: {
                EmptyState(title: t("response.empty"), hint: t("response.emptyHint"))
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) { ProjectSwitcher() }
        }
        .toolbar(removing: .title)
        .overlay(alignment: .bottom) { ToastStack(center: model.toasts) }
        .background(BackingScaleReader(scale: $scale))
        .environment(\.appFonts, fonts)
        .font(fonts.ui)
        .frame(minWidth: 900, minHeight: 600)
        .task {
            await model.projects.restore()
            #if DEBUG
            DebugTools.runIfRequested()
            #endif
        }
    }

    @ViewBuilder private var sidebar: some View {
        if model.projects.active != nil {
            TreeOutlineView(store: model.tree, version: model.tree.version, pendingEdit: model.tree.pendingEdit,
                            font: AppFonts.forScale(scale).uiNSFont)
                .task(id: model.projects.activeID) { await model.tree.load(model.projects.activeID) }
        } else if model.projects.restored {
            EmptyState(title: t("sidebar.noProject"))
        } else {
            Color.clear
        }
    }
}
