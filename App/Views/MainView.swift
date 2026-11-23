import SwiftUI

/// Rozvržení hlavního okna: sidebar | request / odpověď. Šířku sidebaru a rámec okna ukládá AppKit
/// (autosave `NSSplitView`/`NSWindow`), výšku odpovědi workspace.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var scale: CGFloat = 2
    @State private var sidebarTab = 0

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
                requestPane
            } bottom: {
                if let tab = model.tabs.active, let run = model.runs.run(tab.id) {
                    ResponsePane(tabID: tab.id, run: run, section: tab.responseSection)
                } else {
                    EmptyState(title: t("response.empty"), hint: t("response.emptyHint"))
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) { EnvironmentPicker() }
                ToolbarItem(placement: .primaryAction) { VarsOverviewButton() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) { ProjectSwitcher() }
        }
        .toolbar(removing: .title)
        .task(id: model.vars.key) { await model.vars.refresh() }
        .sheet(isPresented: $model.showEnvironments) { EnvironmentsSheet() }
        .sheet(item: $model.scopeSettings) { ScopeSettingsSheet(target: $0) }
        .overlay(alignment: .bottom) { ToastStack(center: model.toasts) }
        .background(BackingScaleReader(scale: $scale))
        .background(MainWindowHook(edited: model.tabs.anyDirty) { [tabs = model.tabs] in tabs.mainWindow = $0 })
        .environment(\.appFonts, fonts)
        .font(fonts.ui)
        .frame(minWidth: 900, minHeight: 600)
        .task {
            await model.projects.restore()
            #if DEBUG
            DebugTools.runIfRequested(model)
            #endif
        }
    }

    @ViewBuilder private var requestPane: some View {
        VStack(spacing: 0) {
            if model.projects.active != nil { TabBar() }
            if let tab = model.tabs.active {
                RequestEditor(tab: tab).id(tab.projectID + "/" + tab.id)
            } else {
                EmptyState(title: t("request.empty"), hint: t("request.emptyHint"))
            }
        }
    }

    @ViewBuilder private var sidebar: some View {
        if model.projects.active != nil {
            VStack(spacing: 0) {
                Picker("", selection: $sidebarTab) {
                    Text(t("sidebar.project")).tag(0)
                    Text(t("sidebar.history")).tag(1)
                }
                .pickerStyle(.segmented).labelsHidden()
                .padding(.horizontal, 8).padding(.top, 6)
                if sidebarTab == 0 {
                    TreeSidebar(font: AppFonts.forScale(scale).uiNSFont)
                } else {
                    HistoryView()
                }
            }
            .task(id: model.projects.activeID) { await model.tree.load(model.projects.activeID) }
        } else if model.projects.restored {
            EmptyState(title: t("sidebar.noProject"))
        } else {
            Color.clear
        }
    }
}
