import SwiftUI

/// Pole hledání nad stromem projektu. Esc vymaže filtr (prázdné pole vrátí fokus do stromu), ↓/Enter přejde do stromu.
struct TreeSidebar: View {
    @Environment(AppModel.self) private var model
    let font: NSFont

    var body: some View {
        @Bindable var tree = model.tree
        VStack(spacing: 0) {
            TextField(t("tree.search"), text: $tree.query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .onSubmit { tree.focusTree() }
                .onKeyPress(.downArrow) {
                    tree.focusTree()
                    return .handled
                }
                .onKeyPress(.escape) {
                    if tree.query.isEmpty { tree.focusTree() } else { tree.query = "" }
                    return .handled
                }
            TreeOutlineView(
                store: tree, version: tree.version, query: tree.query, pendingEdit: tree.pendingEdit,
                focusRequest: tree.focusRequest, font: font
            )
            .overlay {
                if tree.filtering, tree.visibleRoot?.children.isEmpty ?? true {
                    Text(t("tree.noMatches")).foregroundStyle(.secondary)
                }
            }
        }
    }
}
