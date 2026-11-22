import AppKit
import SwiftUI

/// Fonty dle displeje: ne-retina Menlo 13 pro UI i kód, retina systémový font a SF Mono.
struct AppFonts: Equatable, Sendable {
    var isRetina: Bool
    var size: CGFloat = 13

    var ui: Font { uiFont(size) }
    /// Menší text (nápovědy, popisky).
    var small: Font { uiFont(size - 1) }
    var code: Font { isRetina ? .system(size: size, design: .monospaced) : .custom("Menlo", size: size) }

    @MainActor var codeNSFont: NSFont {
        isRetina ? .monospacedSystemFont(ofSize: size, weight: .regular)
            : NSFont(name: "Menlo", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private func uiFont(_ size: CGFloat) -> Font {
        isRetina ? .system(size: size) : .custom("Menlo", size: size)
    }

    static func forScale(_ scale: CGFloat) -> AppFonts { AppFonts(isRetina: scale >= 2) }
}

extension EnvironmentValues {
    @Entry var appFonts = AppFonts(isRetina: true)
}

/// Hlásí `backingScaleFactor` okna, ve kterém leží (i po přesunu na jiný monitor).
struct BackingScaleReader: NSViewRepresentable {
    @Binding var scale: CGFloat

    func makeNSView(context: Context) -> ScaleView {
        let view = ScaleView()
        view.onChange = { scale = $0 }
        return view
    }

    func updateNSView(_ view: ScaleView, context: Context) {
        view.onChange = { scale = $0 }
    }

    final class ScaleView: NSView {
        var onChange: ((CGFloat) -> Void)?
        private var last: CGFloat = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            report()
        }

        private func report() {
            guard let s = window?.backingScaleFactor, s != last else { return }
            last = s
            DispatchQueue.main.async { [weak self] in self?.onChange?(s) }
        }
    }
}
