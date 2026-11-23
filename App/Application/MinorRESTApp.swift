import AppKit
import SwiftUI

@main
struct MinorRESTApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    private var model: AppModel { delegate.model }

    var body: some Scene {
        Window("MinorREST", id: "main") {
            MainView()
                .environment(model)
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Ukončení (Cmd+Q, zavření hlavního okna) s neuloženými taby: Uložit / Neukládat / Zrušit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) { model.updates.start() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Smaže temp soubory těl odpovědí; engine běží mimo hlavní vlákno, čekání je omezené.
    func applicationWillTerminate(_ notification: Notification) {
        model.updates.installIfReadyOnQuit()
        let done = DispatchSemaphore(value: 0)
        let engine = model.runs.engine
        Task.detached {
            await engine.close()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch model.tabs.askBeforeQuit() {
        case nil: return .terminateCancel
        case false?: return .terminateNow
        case true?:
            Task { NSApp.reply(toApplicationShouldTerminate: await model.tabs.saveAll()) }
            return .terminateLater
        }
    }
}
