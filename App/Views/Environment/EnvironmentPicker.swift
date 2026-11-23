import MinorRESTCore
import SwiftUI

/// Výběr prostředí aktivního projektu v toolbaru: žádné, seznam, správa (PLAN 8.5).
struct EnvironmentPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pid = model.projects.activeID
        let envs = model.environments
        let active = envs.active(pid)
        Menu {
            item(t("env.none"), checked: active == nil) { envs.select(pid, nil) }
            if !envs.environments(pid).isEmpty { Divider() }
            ForEach(envs.environments(pid), id: \.id) { e in
                item(e.name, checked: e.id == active?.id) { envs.select(pid, e.id) }
            }
            Divider()
            Button(t("env.manage")) { model.notImplemented("env.manage") }
        } label: {
            Text(active.map { t("env.title", ["name": $0.name]) } ?? t("env.none"))
        }
        .disabled(model.projects.active == nil)
        .task(id: model.projects.active?.id) { if let id = model.projects.active?.id { await envs.load(id) } }
    }

    @ViewBuilder private func item(_ title: String, checked: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if checked { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }
}
