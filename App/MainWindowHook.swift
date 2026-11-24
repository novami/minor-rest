import AppKit
import SwiftUI

/// Napojí hlavní `NSWindow`: tlačítko zavření ukončí aplikaci přes `applicationShouldTerminate` (dotaz na
/// neuložené taby), `isDocumentEdited` = tečka v zavíracím tlačítku. Delegáta okna vlastní SwiftUI, proto
/// se přesměruje jen akce tlačítka.
struct MainWindowHook: NSViewRepresentable {
    let edited: Bool
    let attach: (NSWindow) -> Void

    func makeNSView(context: Context) -> HookView {
        let val = HookView()
        val.attach = attach
        return val
    }

    func updateNSView(_ val: HookView, context: Context) {
        val.edited = edited
        val.window?.isDocumentEdited = edited
    }

    final class HookView: NSView {
        var attach: ((NSWindow) -> Void)?
        var edited = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let wrd = window else { return }
            if let close = wrd.standardWindowButton(.closeButton) {
                close.target = self
                close.action = #selector(closeClicked)
            }
            wrd.isDocumentEdited = edited
            attach?(wrd)
        }

        @objc private func closeClicked(_ sender: Any?) {
            NSApp.terminate(sender)
        }
    }
}
