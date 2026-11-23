import AppKit
import SwiftUI

/// Napojí hlavní `NSWindow`: tlačítko zavření ukončí aplikaci přes `applicationShouldTerminate` (dotaz na
/// neuložené taby), `isDocumentEdited` = tečka v zavíracím tlačítku. Delegáta okna vlastní SwiftUI, proto
/// se přesměruje jen akce tlačítka.
struct MainWindowHook: NSViewRepresentable {
    let edited: Bool
    let attach: (NSWindow) -> Void

    func makeNSView(context: Context) -> HookView {
        let v = HookView()
        v.attach = attach
        return v
    }

    func updateNSView(_ v: HookView, context: Context) {
        v.edited = edited
        v.window?.isDocumentEdited = edited
    }

    final class HookView: NSView {
        var attach: ((NSWindow) -> Void)?
        var edited = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window else { return }
            if let close = w.standardWindowButton(.closeButton) {
                close.target = self
                close.action = #selector(closeClicked)
            }
            w.isDocumentEdited = edited
            attach?(w)
        }

        @objc private func closeClicked(_ sender: Any?) {
            NSApp.terminate(sender)
        }
    }
}
