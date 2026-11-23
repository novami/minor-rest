import AppKit
import MinorRESTCore

/// Ladicí přepínače pro ověřování UI z příkazové řádky (jen Debug build, bez oprávnění k nahrávání obrazovky):
/// `--snapshot <soubor.png>` vykreslí hlavní okno do PNG, `--dump-menu <soubor.txt>` vypíše menu,
/// `--snapshot-delay <s>` odloží snímek (výchozí 1,5 s),
/// `--quit-after-debug` pak aplikaci ukončí, `--workspace-dir <adresář>` použije jiný adresář pro
/// `workspace.yaml` (testy nesahají na skutečný), `--section <params|body|headers|settings|docs>` výchozí záložka
/// otevřených tabů, `--debug-edit-docs <text>` po startu přepíše dokumentaci aktivního tabu (neuložený stav),
/// `--debug-send` po startu odešle aktivní tab, `--response-mode <pretty|raw|preview>` pak přepne pohled těla,
/// `--response-section <body|headers|cookies|timing|sent|redirects>` záložku odpovědi, `--response-filter <jsonpath>` filtr těla,
/// `--debug-env <název>` vybere prostředí aktivního projektu, `--debug-secret <název>=<hodnota>` do něj uloží tajnou proměnnou. Jazyk lze vynutit standardním `-AppleLanguages '(en)'`.
enum DebugTools {
    /// Náhradní adresář workspace (`--workspace-dir`), v Release vždy `nil`.
    static var workspaceDirectory: URL? {
        #if DEBUG
        value("--workspace-dir").map { URL(fileURLWithPath: $0) }
        #else
        nil
        #endif
    }

    /// Výchozí záložka editoru (`--section`), v Release vždy `nil`.
    static var initialSection: String? {
        #if DEBUG
        value("--section")
        #else
        nil
        #endif
    }

    /// Výchozí záložka sidebaru (`--sidebar-tab history`), v Release vždy 0.
    static var initialSidebarTab: Int {
        #if DEBUG
        value("--sidebar-tab") == "history" ? 1 : 0
        #else
        0
        #endif
    }

    private static func value(_ flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        return args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    }
}

#if DEBUG
@MainActor
extension DebugTools {
    static func runIfRequested(_ model: AppModel) {
        let args = ProcessInfo.processInfo.arguments
        if let docs = value("--debug-edit-docs") {
            Task {
                try? await Task.sleep(for: .seconds(1))
                model.tabs.edit { $0.draft.docs = docs }
            }
        }
        if let env = value("--debug-env") {
            Task {
                try? await Task.sleep(for: .seconds(0.5))
                await selectEnvironment(model, env, secret: value("--debug-secret"))
            }
        }
        if args.contains("--debug-send") {
            Task {
                try? await Task.sleep(for: .seconds(1))
                model.send()
                if let mode = value("--response-mode").flatMap(BodyMode.init), let tab = model.tabs.active {
                    try? await Task.sleep(for: .seconds(1))
                    model.runs.setMode(tab.id, mode)
                }
                if let expr = value("--response-filter"), let tab = model.tabs.active {
                    model.runs.filters[tab.id] = expr
                }
                if let section = value("--response-section").flatMap(ResponseSection.init) {
                    model.tabs.edit { $0.responseSection = section }
                }
            }
        }
        if args.contains("--debug-sequence") {
            // Odešle všechny otevřené taby popořadě; `--debug-save N` pak uloží N verzí odpovědi posledního tabu.
            Task {
                try? await Task.sleep(for: .seconds(1))
                for tab in model.tabs.list {
                    model.tabs.activate(tab.id)
                    model.send()
                    try? await Task.sleep(for: .seconds(1.5))
                }
                if let n = value("--debug-save").flatMap(Int.init), let tab = model.tabs.active {
                    for _ in 0..<n {
                        await model.runs.saveResponse(tab.id, projectID: tab.projectID, requestID: tab.draft.id)
                    }
                }
                if let section = value("--response-section").flatMap(ResponseSection.init) {
                    model.tabs.edit { $0.responseSection = section }
                }
            }
        }
        let snapshot = value("--snapshot"), menu = value("--dump-menu")
        guard snapshot != nil || menu != nil else { return }
        Task {
            try? await Task.sleep(for: .seconds(value("--snapshot-delay").flatMap(Double.init) ?? 1.5))
            if let snapshot { writeSnapshot(to: snapshot) }
            if let menu { try? dumpMenu().write(toFile: menu, atomically: true, encoding: .utf8) }
            if args.contains("--quit-after-debug") { NSApp.terminate(nil) }
        }
    }

    private static func selectEnvironment(_ model: AppModel, _ name: String, secret: String?) async {
        let pid = model.projects.activeID
        await model.environments.load(pid)
        guard var env = model.environments.environments(pid).first(where: { $0.name == name }) else { return }
        model.environments.select(pid, env.id)
        guard let secret, let eq = secret.firstIndex(of: "="),
              let project = try? await model.projects.project(pid) else { return }
        let v = Var(name: String(secret[..<eq]), value: String(secret[secret.index(after: eq)...]), secret: true)
        env.vars.removeAll { $0.name == v.name }
        env.vars.append(v)
        do {
            try project.saveEnvironment(env, secrets: model.environments.secrets)
        } catch {
            log.error("debug-secret: \(String(describing: error))")
        }
        await model.environments.load(pid)
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
