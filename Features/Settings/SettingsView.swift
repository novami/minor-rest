import MinorUpdater
import SwiftUI

/// Okno Nastavení (Cmd+,); zatím jen sekce Aktualizace, ostatní přibudou v F11.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var updater = model.updater
        Form {
            Section(t("updates.section")) {
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
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 300)
        .navigationTitle(t("settings.title"))
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
