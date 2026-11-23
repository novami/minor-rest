import AppKit
import MinorRESTCore
import SwiftUI

/// Editor kódu (PLAN 1.1/10): `NSTextView` s TextKit 2, zvýraznění syntaxe a `{{proměnných}}` přes rendering
/// attributes (nemění text, undo ani layout; počítají se jen pro vykreslované fragmenty), hledání `NSTextFinder`.
struct CodeTextView: NSViewRepresentable {
    @Binding var text: String
    var lang: SyntaxLang = .text
    var editable = true
    var font: NSFont
    /// Změna hodnoty otevře find bar (tlačítko hledání v odpovědi).
    var findTrigger = 0

    /// Nad tímto počtem UTF-16 jednotek se syntaxe nezvýrazňuje (proměnné ano).
    static let syntaxLimit = 1_000_000

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = NSTextView(usingTextLayoutManager: true)
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = .width
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.delegate = context.coordinator

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.autohidesScrollers = true

        let c = context.coordinator
        c.textView = tv
        tv.textLayoutManager?.renderingAttributesValidator = { [weak c] lm, fragment in
            MainActor.assumeIsolated { c?.render(lm, fragment) }
        }
        tv.font = font
        tv.string = text
        tv.isEditable = editable
        c.relex()
        c.findTrigger = findTrigger
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let tv = c.textView else { return }
        if tv.font != font { tv.font = font }
        if tv.isEditable != editable { tv.isEditable = editable }
        var changed = c.lang != lang
        if tv.string != text {
            c.replace(with: text)
            changed = true
        }
        if changed { c.relex() }
        if c.findTrigger != findTrigger {
            c.findTrigger = findTrigger
            tv.window?.makeFirstResponder(tv)
            let sender = NSMenuItem()
            sender.tag = NSTextFinder.Action.showFindInterface.rawValue
            tv.performTextFinderAction(sender)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextView
        weak var textView: NSTextView?
        var findTrigger = 0
        private(set) var lang: SyntaxLang = .text
        /// Barevné úseky seřazené podle začátku; proměnné až za syntaxí (přebíjí ji).
        private var syntax: [(NSRange, NSColor)] = []
        private var vars: [(NSRange, NSColor)] = []

        init(_ parent: CodeTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            if parent.text != tv.string { parent.text = tv.string }
            relex()
        }

        /// Vnější změna (Formátovat): jako jedna úprava s undo, u read-only prostá náhrada.
        func replace(with text: String) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let all = NSRange(location: 0, length: storage.length)
            if tv.isEditable, tv.shouldChangeText(in: all, replacementString: text) {
                storage.replaceCharacters(in: all, with: text)
                tv.didChangeText()
            } else {
                tv.string = text
            }
        }

        func relex() {
            guard let tv = textView, let lm = tv.textLayoutManager else { return }
            lang = parent.lang
            let s = tv.string
            let colors = Self.colors
            syntax = (s.utf16.count <= CodeTextView.syntaxLimit ? Syntax.tokens(s, lang) : [])
                .map { ($0.range, colors[$0.kind] ?? .textColor) }
            vars = VarToken.scan(s).map { ($0.range, Highlighter.color($0.kind)) }
            lm.invalidateRenderingAttributes(for: lm.documentRange)
            tv.needsDisplay = true
        }

        func render(_ lm: NSTextLayoutManager, _ fragment: NSTextLayoutFragment) {
            guard let tcs = lm.textContentManager as? NSTextContentStorage else { return }
            let doc = tcs.documentRange.location
            let fr = fragment.rangeInElement
            let range = NSRange(location: tcs.offset(from: doc, to: fr.location),
                                length: tcs.offset(from: fr.location, to: fr.endLocation))
            lm.removeRenderingAttribute(.foregroundColor, for: fr)
            for list in [syntax, vars] {
                for (r, color) in Self.overlapping(list, range) {
                    let lo = max(r.location, range.location), hi = min(NSMaxRange(r), NSMaxRange(range))
                    guard lo < hi, let start = tcs.location(doc, offsetBy: lo),
                          let end = tcs.location(start, offsetBy: hi - lo),
                          let tr = NSTextRange(location: start, end: end) else { continue }
                    lm.addRenderingAttribute(.foregroundColor, value: color, for: tr)
                }
            }
        }

        /// Úseky protínající `range` (seznam je seřazený a nepřekrývající se → binární hledání začátku).
        private static func overlapping(_ list: [(NSRange, NSColor)], _ range: NSRange) -> ArraySlice<(NSRange, NSColor)> {
            var lo = 0, hi = list.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if NSMaxRange(list[mid].0) <= range.location { lo = mid + 1 } else { hi = mid }
            }
            var end = lo
            while end < list.count, list[end].0.location < NSMaxRange(range) { end += 1 }
            return list[lo..<end]
        }

        private static let colors: [SyntaxToken.Kind: NSColor] = [
            .string: NSColor(named: "CodeString") ?? .systemRed,
            .number: NSColor(named: "CodeNumber") ?? .systemGreen,
            .property: NSColor(named: "CodeProperty") ?? .systemBlue,
            .keyword: NSColor(named: "CodeKeyword") ?? .systemPurple,
            .comment: .secondaryLabelColor,
        ]
    }
}
