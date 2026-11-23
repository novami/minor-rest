import SwiftUI

/// Lišta tabů aktivního projektu: metoda, název ze stromu, tečka = neuloženo (při najetí ×), + = nový request.
struct TabBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appFonts) private var fonts

    var body: some View {
        let tabs = model.tabs
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(tabs.projectTabs) { tab in
                        TabItem(tab: tab, name: tabs.name(tab), active: tab.id == tabs.activeID)
                    }
                }
            }
            .scrollIndicators(.never)
            Button { Task { await model.tree.createRequest(near: nil) } } label: {
                Image(systemName: "plus").frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help(t("tree.newRequest"))
        }
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct TabItem: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appFonts) private var fonts
    let tab: RequestTab
    let name: String
    let active: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Text(tab.draft.method)
                .font(.system(size: max(fonts.size - 3, 9), weight: .bold, design: .monospaced))
                .foregroundStyle(methodColor(tab.draft.method))
            Text(name).lineLimit(1).truncationMode(.tail)
            Button { Task { await model.tabs.close(tab.id) } } label: {
                Group {
                    if tab.dirty && !hover {
                        Image(systemName: "circle.fill").font(.system(size: 7))
                    } else {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                    }
                }
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(hover || active || tab.dirty ? 1 : 0)
            .help(t("tabs.close"))
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(maxWidth: 220, maxHeight: .infinity)
        .background(active ? Color(nsColor: .controlBackgroundColor) : .clear)
        .overlay(alignment: .bottom) {
            if active { Rectangle().fill(Color.accentColor).frame(height: 2) }
        }
        .overlay(alignment: .trailing) { Divider() }
        .contentShape(Rectangle())
        .onTapGesture { model.tabs.activate(tab.id) }
        .onHover { hover = $0 }
        .help(tab.rel)
    }
}
