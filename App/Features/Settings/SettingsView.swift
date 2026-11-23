import MinorRESTCore
import SwiftUI

/// Okno Nastavení (Cmd+,); zatím jen sekce Aktualizace, ostatní přibudou v F11.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var updates = model.updates
        Form {
            Section(t("updates.section")) {
                Toggle(t("updates.autoCheck"), isOn: $updates.autoCheck)
                Toggle(t("updates.autoDownload"), isOn: $updates.autoDownload)
                    .disabled(!updates.autoCheck)
                Text(t("updates.autoDownload.hint")).font(.caption).foregroundStyle(.secondary)
                LabeledContent(t("updates.currentVersion"), value: updates.currentVersion.description)
                if let info = updates.info {
                    LabeledContent(t("updates.availableVersion"), value: info.version.description)
                }
                if let notes = updates.info?.notes, !notes.isEmpty {
                    LabeledContent(t("updates.releaseNotes")) { Text(notes).lineLimit(4).textSelection(.enabled) }
                }
                LabeledContent(t("updates.status"), value: updates.statusText)
                HStack {
                    Button(t("updates.checkNow")) { Task { await updates.check(manual: true) } }
                    if case .available = updates.state {
                        Button(t("updates.download")) { Task { await updates.download() } }
                    }
                    if case .ready = updates.state {
                        Button(t("updates.restart")) { updates.installAndRestart() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 340)
        .navigationTitle(t("settings.title"))
    }
}
