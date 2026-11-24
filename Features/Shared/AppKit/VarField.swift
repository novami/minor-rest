import AppKit
import SwiftUI

/// Jednořádkové pole se zvýrazněním `{{proměnných}}` (PLAN 1.1/9): vlastní field editor (TextKit 1),
/// barvy přes temporary attributes layout manageru – nemění text ani undo. Mimo editaci obarvený `attributedStringValue`.
/// S `varContext` z prostředí: známá zeleně, neznámá červeně, hover = popover s hodnotou, po `{{` našeptávač názvů.
struct VarField: NSViewRepresentable {
    @Binding var text: String
    var placeholder = ""
    var font: NSFont
    /// Zvýšení = vzít fokus.
    var focusRequest = 0
    var onSubmit: (() -> Void)?
    /// Našeptávač: návrhy k celému textu pole (nabízí se při psaní).
    var completions: ((String) -> [String])?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> VarTextField {
        let field = VarTextField()
        field.cell = VarFieldCell(textCell: "")
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.allowsEditingTextAttributes = false
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        context.coordinator.focusRequest = focusRequest
        return field
    }

    func updateNSView(_ field: VarTextField, context: Context) {
        let cur = context.coordinator
        cur.parent = self
        if field.font != font { field.font = font }
        field.placeholderString = placeholder
        let vars = context.environment.varContext
        let varsChanged = field.vars != vars
        field.vars = vars
        if field.stringValue != text || varsChanged {
            if let editor = field.currentEditor() as? NSTextView {
                if editor.string != text { editor.string = text }
                Highlighter.apply(editor, vars)
            } else if field.stringValue != text {
                field.stringValue = text
            }
        }
        if field.currentEditor() == nil { Highlighter.display(field, vars) }
        if cur.focusRequest != focusRequest {
            cur.focusRequest = focusRequest
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: VarField
        var focusRequest = 0
        private var completing = false
        private var lastLength = 0

        init(_ parent: VarField) { self.parent = parent }

        func controlTextDidBeginEditing(_ notification: Notification) {
            lastLength = (notification.object as? NSTextField)?.stringValue.utf16.count ?? 0
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let vars = (field as? VarTextField)?.vars
            let editor = field.currentEditor() as? VarFieldEditor
            if let editor { Highlighter.apply(editor, vars) }
            if parent.text != field.stringValue { parent.text = field.stringValue }
            // návrhy jen při přidání textu (ne při mazání) a ne během vložení vybraného návrhu
            let length = field.stringValue.utf16.count
            defer { lastLength = length }
            guard !completing, length > lastLength, let editor, !editor.insertingCompletion else { return }
            // bez návrhů by complete() pípnul
            if let range = editor.varPartialRange {
                let prefix = (editor.string as NSString).substring(with: range)
                guard !VarContext.completions(vars, prefix).isEmpty else { return }
                editor.completingVar = true
            } else {
                guard let completions = parent.completions, !completions(editor.string).isEmpty else { return }
                editor.completingVar = false
            }
            completing = true
            editor.complete(nil)
            completing = false
        }

        func control(_ control: NSControl, textView: NSTextView, completions words: [String],
                     forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
            index.pointee = -1   // nic nevkládat, dokud uživatel návrh nevybere
            if let editor = textView as? VarFieldEditor, editor.completingVar {
                let prefix = (textView.string as NSString).substring(with: charRange)
                return VarContext.completions((control as? VarTextField)?.vars, prefix)
            }
            return parent.completions?(textView.string) ?? []
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? VarTextField else { return }
            Highlighter.display(field, field.vars)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)), let onSubmit = parent.onSubmit else { return false }
            onSubmit()
            return true
        }
    }
}

final class VarTextField: NSTextField {
    var vars: VarContext?
    private var hoverArea: NSTrackingArea?
    private var hoverToken: VarToken?
    private var hoverTask: Task<Void, Never>?
    private var popover: NSPopover?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let tok = token(atX: convert(event.locationInWindow, from: nil).x)
        guard tok != hoverToken else { return }
        hideHover()
        hoverToken = tok
        guard let tok else { return }
        let x = convert(event.locationInWindow, from: nil).x
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.showHover(tok, atX: x)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoverToken = nil
        hideHover()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { hideHover() }
        super.viewWillMove(toWindow: newWindow)
    }

    private func hideHover() {
        hoverTask?.cancel()
        hoverTask = nil
        popover?.close()
        popover = nil
    }

    private func showHover(_ tok: VarToken, atX x: CGFloat) {
        guard window != nil else { return }
        let par = NSPopover()
        par.behavior = .semitransient
        par.animates = false
        par.contentViewController = NSHostingController(rootView: VarHoverView(name: tok.name, info: vars?.byName[tok.name],
                                                                              known: vars?.isKnown(tok.name)))
        par.show(relativeTo: NSRect(x: x, y: 0, width: 1, height: bounds.height), of: self,
               preferredEdge: isFlipped ? .maxY : .minY)
        popover = par
    }

    /// Token proměnné pod vodorovnou souřadnicí (v editaci podle field editoru, jinak rozložením zobrazeného textu).
    private func token(atX x: CGFloat) -> VarToken? {
        let text = stringValue
        let tokens = VarToken.scan(text)
        guard !tokens.isEmpty, let index = charIndex(atX: x, text: text) else { return nil }
        return tokens.first { NSLocationInRange(index, $0.range) }
    }

    private func charIndex(atX x: CGFloat, text: String) -> Int? {
        let lm: NSLayoutManager, tc: NSTextContainer, local: CGFloat
        if let editor = currentEditor() as? NSTextView, let elm = editor.layoutManager, let etc = editor.textContainer {
            (lm, tc) = (elm, etc)
            local = editor.convert(NSPoint(x: x, y: 0), from: self).x - editor.textContainerOrigin.x
        } else {
            guard let cell else { return nil }
            let storage = NSTextStorage(attributedString: attributedStringValue)
            lm = NSLayoutManager()
            tc = NSTextContainer(size: NSSize(width: 1e6, height: 1e6))
            lm.addTextContainer(tc)
            storage.addLayoutManager(lm)
            local = x - cell.titleRect(forBounds: bounds).minX
        }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        guard local >= used.minX, local <= used.maxX else { return nil }
        var fraction: CGFloat = 0
        let glyph = lm.glyphIndex(for: NSPoint(x: local, y: used.midY), in: tc, fractionOfDistanceThroughGlyph: &fraction)
        return lm.characterIndexForGlyph(at: glyph)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok, let editor = currentEditor() as? NSTextView {
            // field editor převezme obarvený text – barvy z textu odstranit, zvýraznění jen dočasnými atributy
            if let storage = editor.textStorage, storage.length > 0 {
                storage.addAttribute(.foregroundColor, value: NSColor.textColor,
                                     range: NSRange(location: 0, length: storage.length))
            }
            Highlighter.apply(editor, vars)
        }
        return ok
    }
}

/// Buňka s vlastním field editorem (TextKit 1 kvůli temporary attributes, bez automatických náhrad).
final class VarFieldCell: NSTextFieldCell {
    private var editor: NSTextView?

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        if let editor { return editor }
        let tv = VarFieldEditor(usingTextLayoutManager: false)
        tv.isFieldEditor = true
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.smartInsertDeleteEnabled = false
        editor = tv
        return tv
    }
}

/// Field editor: návrh nahrazuje celý text pole (názvy hlaviček obsahují `-`), u proměnné jen název za `{{`.
final class VarFieldEditor: NSTextView {
    /// Probíhá našeptávání názvu proměnné (jinak celého textu).
    var completingVar = false

    override var rangeForUserCompletion: NSRange {
        if completingVar, let res = varPartialRange { return res }
        return NSRange(location: 0, length: (string as NSString).length)
    }

    /// Rozepsaný název za posledním `{{` před kurzorem (`\{{` je literál), jinak `nil`.
    var varPartialRange: NSRange? {
        let sel = selectedRange()
        guard sel.length == 0 else { return nil }
        let pre = (string as NSString).substring(to: sel.location) as NSString
        let open = pre.range(of: "{{", options: .backwards)
        guard open.location != NSNotFound,
              open.location == 0 || pre.character(at: open.location - 1) != 0x5C else { return nil }
        let start = open.location + 2
        let partial = pre.substring(from: start)
        guard partial.unicodeScalars.enumerated().allSatisfy({ i, cur in
            (i == 0 && cur == "$") || CharacterSet.alphanumerics.contains(cur) && cur.isASCII || "_.-".unicodeScalars.contains(cur)
        }) else { return nil }
        return NSRange(location: start, length: sel.location - start)
    }

    /// Vkládá se návrh z nabídky (šipky, Enter) – nespouštět nové našeptávání.
    private(set) var insertingCompletion = false

    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange,
                                   movement: Int, isFinal flag: Bool) {
        insertingCompletion = true
        defer { insertingCompletion = false }
        super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
        guard flag else { return }
        defer { completingVar = false }
        // vybraný název proměnné (Enter/Tab) doplní uzavírací `}}`, pokud za kurzorem ještě není
        guard completingVar, movement == NSTextMovement.return.rawValue || movement == NSTextMovement.tab.rawValue
        else { return }
        let rest = (string as NSString).substring(from: selectedRange().location)
        if !rest.hasPrefix("}}") { insertText("}}", replacementRange: selectedRange()) }
    }
}

/// Barvy tokenů proměnných: dynamická `$` modře, ostatní zeleně; s kontextem neznámá červeně.
@MainActor
enum Highlighter {
    static func color(_ tok: VarToken, _ vars: VarContext?) -> NSColor {
        if let vars, !vars.isKnown(tok.name) { return .systemRed }
        return tok.kind == .dynamic ? .systemBlue : .systemGreen
    }

    /// Zvýraznění v editoru (temporary attributes – nejdou do textu ani do undo).
    static func apply(_ editor: NSTextView, _ vars: VarContext?) {
        guard let lm = editor.layoutManager else { return }
        let all = NSRange(location: 0, length: (editor.string as NSString).length)
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: all)
        for tok in VarToken.scan(editor.string) {
            lm.addTemporaryAttribute(.foregroundColor, value: color(tok, vars), forCharacterRange: tok.range)
        }
    }

    /// Obarvený text pole mimo editaci.
    static func display(_ field: NSTextField, _ vars: VarContext?) {
        let str = field.stringValue
        let tokens = VarToken.scan(str)
        let attr = NSMutableAttributedString(string: str, attributes: [
            .font: field.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.textColor,
        ])
        for tok in tokens { attr.addAttribute(.foregroundColor, value: color(tok, vars), range: tok.range) }
        if field.attributedStringValue != attr { field.attributedStringValue = attr }
    }
}

/// Obsah hover popoveru nad proměnnou: hodnota (tajná `••••`) a zdroj, nebo „neznámá“.
struct VarHoverView: View {
    let name: String
    let info: VarInfo?
    /// `nil` = bez kontextu (jen název).
    let known: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.system(.body, design: .monospaced)).bold()
            if let info {
                Text(info.secret ? "••••" : info.resolved)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(4).textSelection(.enabled)
                if !info.secret && info.value != info.resolved {
                    Text(info.value).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(VarSourceText.text(info)).font(.caption).foregroundStyle(.secondary)
            } else if name.hasPrefix("$") && known != false {
                Text(t("vars.dynamic")).font(.caption).foregroundStyle(.secondary)
            } else if known == false {
                Text(t("vars.unknown")).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(10)
        .frame(maxWidth: 420, alignment: .leading)
    }
}

@MainActor
enum VarSourceText {
    /// „Složka: api/users“, „Prostředí“ …
    static func text(_ info: VarInfo) -> String {
        let str = t("vars.source." + info.source.rawValue)
        return info.ref.isEmpty ? str : str + ": " + info.ref
    }
}
