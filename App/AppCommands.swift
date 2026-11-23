import SwiftUI

/// Hlavní menu a zkratky (PLAN 8.7) – jediný zdroj zkratek.
struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(t("menu.newRequest")) { Task { await model.tree.createRequest(near: nil) } }
                .keyboardShortcut("n")
            Button(t("menu.newFolder")) { Task { await model.tree.createFolder(near: nil) } }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .saveItem) {
            Button(t("menu.save")) { Task { await model.tabs.save() } }
                .keyboardShortcut("s")
            item("menu.saveResponse", "s", [.command, .shift])
            Divider()
            Button(t("menu.closeTab")) { Task { await model.tabs.close() } }
                .keyboardShortcut("w")
        }
        CommandMenu(t("menu.request")) {
            item("menu.send", .return)
            item("menu.cancel", ".")
            Divider()
            item("menu.copyCurl", "c", [.command, .shift])
            Button(t("menu.duplicate")) { Task { await model.tree.duplicate(model.tree.selection) } }
                .keyboardShortcut("d")
            Button(t("menu.focusUrl")) { model.tabs.focusURL() }
                .keyboardShortcut("l")
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
