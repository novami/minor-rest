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
            Picker(t("settings.theme"), selection: $store.value.general.theme) {
                Text(t("settings.theme.system")).tag("system")
                Text(t("settings.theme.light")).tag("light")
                Text(t("settings.theme.dark")).tag("dark")
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
        Form {
            Toggle(t("settings.followRedirects"), isOn: $store.value.requests.followRedirects)
            NumberField(t("settings.maxRedirects"), value: $store.value.requests.maxRedirects)
                .disabled(!store.value.requests.followRedirects)
            NumberField(t("settings.timeout"), value: $store.value.requests.timeoutMs)
            Toggle(t("settings.verifyTLS"), isOn: $store.value.requests.verifyTLS)
            Toggle(t("settings.cookieJar"), isOn: $store.value.requests.cookieJar)
            TextField(t("settings.userAgent"), text: $store.value.requests.userAgent, prompt: Text(store.userAgent))
            Text(t("settings.requestsHint")).font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct ProxySettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var store = model.settings
        Form {
            Picker(t("settings.proxy.mode"), selection: $store.value.proxy.mode) {
                Text(t("settings.proxy.system")).tag("system")
                Text(t("settings.proxy.none")).tag("none")
                Text(t("settings.proxy.manual")).tag("manual")
            }
            if store.value.proxy.mode == "manual" {
                TextField(t("settings.proxy.host"), text: $store.value.proxy.host)
                NumberField(t("settings.proxy.port"), value: $store.value.proxy.port)
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
            NumberField(t("settings.maxBody"), value: $store.value.responses.maxBodyMB)
            NumberField(t("settings.historyLimit"), value: $store.value.responses.historyLimit)
            NumberField(t("settings.autoPretty"), value: $store.value.responses.autoPrettyMB)
        }
        .formStyle(.grouped)
    }
}

struct CopySettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var store = model.settings
        Form {
            Picker(t("settings.copyFormat"), selection: $store.value.copy.multiline) {
                Text(t("curl.multiline")).tag(true)
                Text(t("curl.oneline")).tag(false)
            }
            Toggle(t("curl.mask"), isOn: $store.value.copy.maskSecrets)
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
