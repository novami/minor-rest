#if DEBUG
import AppKit

/// Ladicí přepínače pro ověřování UI z příkazové řádky (bez oprávnění k nahrávání obrazovky):
/// `--snapshot <soubor.png>` vykreslí hlavní okno do PNG, `--dump-menu <soubor.txt>` vypíše menu,
/// `--quit-after-debug` pak aplikaci ukončí. Jazyk lze vynutit standardním `-AppleLanguages '(en)'`.
@MainActor
enum DebugTools {
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        let snapshot = value("--snapshot"), menu = value("--dump-menu")
        guard snapshot != nil || menu != nil else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if let snapshot { writeSnapshot(to: snapshot) }
            if let menu { try? dumpMenu().write(toFile: menu, atomically: true, encoding: .utf8) }
            if args.contains("--quit-after-debug") { NSApp.terminate(nil) }
        }
    }

    private static func writeSnapshot(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private static func dumpMenu() -> String {
        var out = ""
        func walk(_ menu: NSMenu, _ depth: Int) {
            for item in menu.items where !item.isSeparatorItem && !item.isHidden && !item.isAlternate {
                var key = ""
                if !item.keyEquivalent.isEmpty {
                    let m = item.keyEquivalentModifierMask
                    key = (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "")
                        + (m.contains(.shift) ? "⇧" : "") + (m.contains(.command) ? "⌘" : "")
                        + (item.keyEquivalent == "\r" ? "↩" : item.keyEquivalent.uppercased())
                }
                out += String(repeating: "  ", count: depth) + item.title + (key.isEmpty ? "" : "  [\(key)]") + "\n"
                if let sub = item.submenu { walk(sub, depth + 1) }
            }
        }
        if let main = NSApp.mainMenu { walk(main, 0) }
        return out
    }
}
#endif
