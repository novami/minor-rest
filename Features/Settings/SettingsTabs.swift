import AppKit
import SwiftUI

/// Záložky okna Nastavení (kap. 9); změny se projeví ihned.
struct GeneralSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var store = model.settings
        Form {
            Picker(t("settings.language"), selection: $store.value.general.language) {
                Text(t("settings.language.auto")).tag("auto")
                Text("Čeština").tag("cs")
                Text("English").tag("en")
            }
            LabeledContent(t("settings.projectsDir")) {
                HStack {
                    Text(store.value.general.projectsDirectory.path(percentEncoded: false))
                        .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Button(t("project.changeLocation"), action: pickDirectory)
                    Button(t("settings.reset")) { store.value.general.projectsDir = "" }
                        .disabled(store.value.general.projectsDir.isEmpty)
                }
            }
            Toggle(t("settings.restore"), isOn: $store.value.general.restoreSession)
            Section {
                Toggle(t("curl.mask"), isOn: $store.value.copy.maskSecrets)
            } footer: {
                Text(t("curl.maskHint"))
            }
        }
        .formStyle(.grouped)
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = model.settings.value.general.projectsDirectory
        if panel.runModal() == .OK, let url = panel.url { model.settings.value.general.projectsDir = url.path }
    }
}

struct RequestsSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var store = model.settings
        let timeoutSeconds = Binding(
            get: { store.value.requests.timeoutMs / 1000 },
            set: { store.value.requests.timeoutMs = max(0, $0) * 1000 })
        Form {
            Section {
                Toggle(t("settings.followRedirects"), isOn: $store.value.requests.followRedirects)
                NumberField(t("settings.maxRedirects"), value: $store.value.requests.maxRedirects)
                    .disabled(!store.value.requests.followRedirects)
                NumberField(t("settings.timeout"), value: timeoutSeconds)
                Toggle(t("settings.cookieJar"), isOn: $store.value.requests.cookieJar)
                TextField(t("settings.userAgent"), text: $store.value.requests.userAgent, prompt: Text(store.userAgent))
            } header: {
                Text(t("settings.section.requests"))
            } footer: {
                Text(t("settings.requestsHint"))
            }
            Section {
                Toggle(t("settings.verifyTLS"), isOn: $store.value.requests.verifyTLS)
            } header: {
                Text(t("settings.section.advanced"))
            } footer: {
                Text(t("settings.verifyTLS.hint"))
            }
        }
        .formStyle(.grouped)
    }
}

struct ResponsesSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var store = model.settings
        Form {
            Section {
                NumberField(t("settings.maxBody"), value: $store.value.responses.maxBodyMB)
            } footer: {
                Text(t("settings.maxBody.hint"))
            }
            Section {
                NumberField(t("settings.historyLimit"), value: $store.value.responses.historyLimit)
            } footer: {
                Text(t("settings.historyLimit.hint"))
            }
            Section {
                NumberField(t("settings.autoPretty"), value: $store.value.responses.autoPrettyMB)
            } footer: {
                Text(t("settings.autoPretty.hint"))
            }
        }
        .formStyle(.grouped)
    }
}

/// Číselné pole, které změnu zapíše po potvrzení.
private struct NumberField: View {
    let title: String
    @Binding var value: Int

    init(_ title: String, value: Binding<Int>) {
        self.title = title
        _value = value
    }

    var body: some View {
        TextField(title, value: $value, format: .number.grouping(.never))
            .multilineTextAlignment(.trailing)
    }
}
