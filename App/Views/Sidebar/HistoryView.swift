import MinorRESTCore
import SwiftUI

/// Záložka Historie: poslední odeslání aktivního projektu; klik otevře detail jen pro čtení.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appFonts) private var fonts
    @State private var opened: Opened?

    struct Opened: Identifiable {
        let id: String
        let entry: SavedResponse
        let data: Data
    }

    private var items: [HistoryItem] {
        model.runs.historyItems.filter { $0.projectID == model.projects.activeID }
    }

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                Text(t("history.empty")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { row($0) }.listStyle(.plain)
                Divider()
                HStack {
                    Spacer()
                    Button(t("history.clear")) { Task { await model.runs.clearHistory() } }.buttonStyle(.borderless)
                }
                .padding(6)
            }
        }
        .task { await model.runs.loadHistory() }
        .sheet(item: $opened) { o in
            SavedResponseSheet(title: t("history.title"), entry: o.entry, data: o.data,
                               openRequest: o.entry.requestID.isEmpty ? nil : { openRequest(o.entry.requestID) })
        }
    }

    private func row(_ i: HistoryItem) -> some View {
        Button {
            Task {
                if let (e, b) = await model.runs.historyEntry(i.id) { opened = Opened(id: i.id, entry: e, data: b) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(i.method).font(fonts.small.weight(.semibold)).foregroundStyle(methodColor(i.method))
                    Text(i.requestName.isEmpty ? i.url : i.requestName).font(fonts.ui).lineLimit(1)
                    Spacer()
                    Text(i.error.isEmpty ? String(i.status) : "✕")
                        .font(fonts.small).foregroundStyle(i.error.isEmpty ? Color.secondary : Color.red)
                }
                Text(i.url).font(fonts.small).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text(VersionsView.time(i.savedAt)).font(fonts.small).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 3).padding(.horizontal, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func openRequest(_ id: String) {
        guard let node = model.tree.root?.findRequest(id: id) else { return }
        Task { await model.tabs.open(node.rel) }
    }
}
