import AppKit
import MinorUpdater
import SwiftUI

/// Hlavní menu a zkratky (PLAN 8.7) – jediný zdroj zkratek.
struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(t("updates.menuCheck")) { Task { await model.updater.checkForUpdates() } }
                .disabled(!model.updater.isAvailable)
        }
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
            Button(t("menu.send")) { model.send() }
                .keyboardShortcut(.return)
            Button(t("menu.cancel")) { model.cancelRun() }
                .keyboardShortcut(".")
            Divider()
            item("menu.copyCurl", "c", [.command, .shift])
            Button(t("menu.duplicate")) { Task { await model.tree.duplicate(model.tree.selection) } }
                .keyboardShortcut("d")
            Button(t("menu.focusUrl")) { model.tabs.focusURL() }
                .keyboardShortcut("l")
            Divider()
            Button(t("menu.environment")) { model.openEnvironments() }
                .keyboardShortcut("e")
        }
        CommandGroup(after: .textEditing) {
            Divider()
            find("menu.find", .showFindInterface, "f")
            find("menu.findNext", .nextMatch, "g")
            find("menu.findPrevious", .previousMatch, "g", [.command, .shift])
        }
        CommandGroup(replacing: .sidebar) {
            Button(t("menu.toggleSidebar")) { model.toggleSidebar() }
                .keyboardShortcut("b")
            item("menu.palette", "k")
        }
    }

    /// Hledání v textovém poli s fokusem (`NSTextFinder` v `CodeTextView`); akce čte `tag` odesílatele.
    private func find(
        _ key: String, _ action: NSTextFinder.Action, _ shortcut: KeyEquivalent,
        _ modifiers: EventModifiers = .command
    ) -> some View {
        Button(t(key)) {
            let sender = NSMenuItem()
            sender.tag = action.rawValue
            NSApp.sendAction(#selector(NSTextView.performTextFinderAction(_:)), to: nil, from: sender)
        }
        .keyboardShortcut(shortcut, modifiers: modifiers)
    }

    private func item(_ key: String, _ shortcut: KeyEquivalent, _ modifiers: EventModifiers = .command) -> some View {
        Button(t(key)) { model.notImplemented(key) }
            .keyboardShortcut(shortcut, modifiers: modifiers)
    }
}
