import SwiftUI

/// HTTP nastavení requestu: každá položka „Zdědit (aktuálně: …)“ nebo vlastní hodnota (`nil` = zděděno).
/// `httpVersion` a `cookieJar` se jen zachovávají (verzi URLSession neumí vynutit, cookie jar je v nastavení projektu).
struct SettingsEditor: View {
    @Binding var settings: HTTPSettings
    /// Co by request zdědil (projekt → výchozí); `nil` = ještě nenačteno.
    let inherited: HTTPSettings?

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            boolRow("settings.followRedirects", \.followRedirects)
            numberRow("settings.maxRedirects", \.maxRedirects, min: 0, unit: nil)
            numberRow("settings.timeoutMs", \.timeoutMs, min: 1, unit: "ms")
            boolRow("settings.verifyTls", \.verifyTLS)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inheritLabel(_ value: String?) -> String {
        t("settings.inherit", ["value": value ?? "—"])
    }

    private func boolRow(_ key: String, _ path: WritableKeyPath<HTTPSettings, Bool?>) -> some View {
        GridRow {
            Text(t(key)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Picker("", selection: Binding(get: { settings[keyPath: path] }, set: { settings[keyPath: path] = $0 })) {
                Text(inheritLabel(inherited?[keyPath: path].map { t($0 ? "settings.on" : "settings.off") }))
                    .tag(Bool?.none)
                Text(t("settings.on")).tag(Bool?.some(true))
                Text(t("settings.off")).tag(Bool?.some(false))
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private func numberRow(_ key: String, _ path: WritableKeyPath<HTTPSettings, Int?>, min: Int, unit: String?) -> some View {
        let own = settings[keyPath: path]
        return GridRow {
            Text(t(key)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            HStack(spacing: 6) {
                Picker("", selection: Binding(get: { own != nil }, set: { on in
                    settings[keyPath: path] = on ? (inherited?[keyPath: path] ?? min) : nil
                })) {
                    Text(inheritLabel(inherited?[keyPath: path].map { "\($0)" + (unit.map { " \($0)" } ?? "") })).tag(false)
                    Text(t("settings.custom")).tag(true)
                }
                .labelsHidden()
                .fixedSize()
                if let own {
                    TextField("", value: Binding(get: { own }, set: { settings[keyPath: path] = Swift.max(min, $0) }),
                              format: .number.grouping(.never))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    if let unit { Text(unit).foregroundStyle(.secondary) }
                }
            }
        }
    }
}
