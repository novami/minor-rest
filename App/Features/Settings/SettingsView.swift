import SwiftUI

/// Okno Nastavení (Cmd+,) – obsah přibude v F11.
struct SettingsView: View {
    var body: some View {
        EmptyState(title: t("settings.placeholder"))
            .frame(width: 480, height: 240)
            .navigationTitle(t("settings.title"))
    }
}
