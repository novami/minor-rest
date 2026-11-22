import SwiftUI

/// Rozvržení hlavního okna: sidebar | request / odpověď.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var scale: CGFloat = 2

    var body: some View {
        @Bindable var model = model
        let fonts = AppFonts.forScale(scale)
        NavigationSplitView(columnVisibility: $model.columnVisibility) {
            EmptyState(title: t("sidebar.noProject"))
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 600)
        } detail: {
            VSplitView {
                EmptyState(title: t("request.empty"), hint: t("request.emptyHint"))
                    .frame(minHeight: 120, maxHeight: .infinity)
                EmptyState(title: t("response.empty"), hint: t("response.emptyHint"))
                    .frame(minHeight: 120, idealHeight: 300, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .bottom) { ToastStack(center: model.toasts) }
        .background(BackingScaleReader(scale: $scale))
        .environment(\.appFonts, fonts)
        .font(fonts.ui)
        .frame(minWidth: 900, minHeight: 600)
        #if DEBUG
        .task { DebugTools.runIfRequested() }
        #endif
    }
}
