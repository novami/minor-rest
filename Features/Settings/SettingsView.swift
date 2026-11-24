import MinorUpdater
import SwiftUI

/// Okno Nastavení (Cmd+,): záložky Obecné, Requesty, Proxy, Odpovědi, Kopírování, Aktualizace.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            GeneralSettingsTab().tabItem { Label(t("settings.tab.general"), systemImage: "gearshape") }
            RequestsSettingsTab().tabItem { Label(t("settings.tab.requests"), systemImage: "arrow.up.arrow.down") }
            ProxySettingsTab().tabItem { Label(t("settings.tab.proxy"), systemImage: "network") }
            ResponsesSettingsTab().tabItem { Label(t("settings.tab.responses"), systemImage: "doc.text") }
            CopySettingsTab().tabItem { Label(t("settings.tab.copy"), systemImage: "doc.on.doc") }
            updatesTab.tabItem { Label(t("updates.section"), systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 560, height: 340)
        .navigationTitle(t("settings.title"))
    }

    private var updatesTab: some View {
        @Bindable var updater = model.updater
        return Form {
            Toggle(t("updates.autoCheck"), isOn: $updater.automaticChecks)
                .disabled(!updater.isAvailable)
            LabeledContent(t("updates.currentVersion"), value: Self.currentVersion)
            LabeledContent(t("updates.status"), value: statusText(updater.state))
            if case .available(_, let notes?) = updater.state {
                LabeledContent(t("updates.releaseNotes")) { Text(notes).lineLimit(4).textSelection(.enabled) }
            }
            HStack {
                Button(t("updates.checkNow")) { Task { await updater.checkForUpdates() } }
                    .disabled(!updater.isAvailable || updater.state == .checking)
                if case .available = updater.state {
                    Button(t("updates.restart")) { Task { await updater.installUpdate() } }
                }
            }
        }
        .formStyle(.grouped)
    }

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private func statusText(_ state: Updater.State) -> String {
        switch state {
        case .unavailable(let reason): reason
        case .idle: t("updates.status.idle")
        case .checking: t("updates.status.checking")
        case .upToDate: t("updates.status.upToDate")
        case .available(let version, _): t("updates.status.available") + " " + version.description
        case .downloading: t("updates.status.downloading", ["percent": "…"])
        case .failed(let message): message
        }
    }
}
