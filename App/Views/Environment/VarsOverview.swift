import MinorRESTCore
import SwiftUI

/// „Oko“ v toolbaru: popover s platnými proměnnými aktivního tabu (název, hodnota, zdroj), runtime lze smazat (PLAN 8.5).
struct VarsOverviewButton: View {
    @Environment(AppModel.self) private var model
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: { Image(systemName: "eye") }
            .help(t("vars.overview"))
            .disabled(model.projects.active == nil)
            .popover(isPresented: $shown, arrowEdge: .bottom) { VarsOverview() }
    }
}

struct VarsOverview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appFonts) private var fonts

    var body: some View {
        let ctx = model.vars.context
        VStack(alignment: .leading, spacing: 8) {
            Text(t("vars.overview")).font(.headline)
            if let ctx, !ctx.infos.isEmpty {
                ScrollView {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                        ForEach(ctx.infos, id: \.name) { info in
                            GridRow {
                                Text(info.name).font(fonts.code).bold()
                                Text(info.secret ? "••••" : info.resolved)
                                    .font(fonts.code).lineLimit(2).textSelection(.enabled)
                                    .frame(maxWidth: 320, alignment: .leading)
                                Text(VarSourceText.text(info)).font(fonts.small).foregroundStyle(.secondary)
                                if info.source == .runtime {
                                    Button {
                                        model.vars.deleteRuntime(ctx.projectID, info.name)
                                    } label: { Image(systemName: "trash") }
                                        .buttonStyle(.borderless)
                                        .help(t("vars.deleteRuntime"))
                                } else {
                                    Color.clear.frame(width: 1, height: 1)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 400)
            } else {
                Text(t("vars.none")).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(minWidth: 320)
    }
}
