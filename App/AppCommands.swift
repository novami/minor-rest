import SwiftUI

/// Hlavní menu a zkratky (PLAN 8.7) – jediný zdroj zkratek.
struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            item("menu.newRequest", "n")
            item("menu.newFolder", "n", [.command, .shift])
        }
        CommandGroup(replacing: .saveItem) {
            item("menu.save", "s")
            item("menu.saveResponse", "s", [.command, .shift])
            Divider()
            item("menu.closeTab", "w")
        }
        CommandMenu(t("menu.request")) {
            item("menu.send", .return)
            item("menu.cancel", ".")
            Divider()
            item("menu.copyCurl", "c", [.command, .shift])
            item("menu.duplicate", "d")
            item("menu.focusUrl", "l")
            Divider()
            item("menu.environment", "e")
        }
        CommandGroup(replacing: .sidebar) {
            Button(t("menu.toggleSidebar")) { model.toggleSidebar() }
                .keyboardShortcut("b")
            item("menu.palette", "k")
        }
    }

    private func item(_ key: String, _ shortcut: KeyEquivalent, _ modifiers: EventModifiers = .command) -> some View {
        Button(t(key)) { model.notImplemented(key) }
            .keyboardShortcut(shortcut, modifiers: modifiers)
    }
}
