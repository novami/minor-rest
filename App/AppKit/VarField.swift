import AppKit
import MinorRESTCore
import SwiftUI

/// Jednořádkové pole se zvýrazněním `{{proměnných}}` (PLAN 1.1/9): vlastní field editor (TextKit 1),
/// barvy přes temporary attributes layout manageru – nemění text ani undo. Mimo editaci obarvený `attributedStringValue`.
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
        let c = context.coordinator
        c.parent = self
        if field.font != font { field.font = font }
        field.placeholderString = placeholder
        if field.stringValue != text {
            if let editor = field.currentEditor() as? NSTextView {
                editor.string = text
                Highlighter.apply(editor)
            } else {
                field.stringValue = text
            }
        }
        if field.currentEditor() == nil { Highlighter.display(field) }
        if c.focusRequest != focusRequest {
            c.focusRequest = focusRequest
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
            let editor = field.currentEditor() as? NSTextView
            if let editor { Highlighter.apply(editor) }
            if parent.text != field.stringValue { parent.text = field.stringValue }
            // návrhy jen při přidání textu (ne při mazání) a ne během vložení vybraného návrhu
            let length = field.stringValue.utf16.count
            defer { lastLength = length }
            guard let completions = parent.completions, !completing, length > lastLength, let editor,
                  !((editor as? VarFieldEditor)?.insertingCompletion ?? false),
                  !completions(editor.string).isEmpty else { return }   // bez návrhů by complete() pípnul
            completing = true
            editor.complete(nil)
            completing = false
        }

        func control(_ control: NSControl, textView: NSTextView, completions words: [String],
                     forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
            index.pointee = -1   // nic nevkládat, dokud uživatel návrh nevybere
            return parent.completions?(textView.string) ?? []
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            Highlighter.display(field)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)), let onSubmit = parent.onSubmit else { return false }
            onSubmit()
            return true
        }
    }
}

final class VarTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok, let editor = currentEditor() as? NSTextView {
            // field editor převezme obarvený text – barvy z textu odstranit, zvýraznění jen dočasnými atributy
            if let storage = editor.textStorage, storage.length > 0 {
                storage.addAttribute(.foregroundColor, value: NSColor.textColor,
                                     range: NSRange(location: 0, length: storage.length))
            }
            Highlighter.apply(editor)
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

/// Field editor: návrh nahrazuje celý text pole (názvy hlaviček obsahují `-`).
final class VarFieldEditor: NSTextView {
    override var rangeForUserCompletion: NSRange { NSRange(location: 0, length: (string as NSString).length) }

    /// Vkládá se návrh z nabídky (šipky, Enter) – nespouštět nové našeptávání.
    private(set) var insertingCompletion = false

    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange,
                                   movement: Int, isFinal flag: Bool) {
        insertingCompletion = true
        defer { insertingCompletion = false }
        super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
    }
}

/// Barvy tokenů proměnných (zatím jen syntakticky: proměnná zeleně, dynamická `$` modře).
@MainActor
enum Highlighter {
    static func color(_ kind: VarToken.Kind) -> NSColor {
        kind == .dynamic ? .systemBlue : .systemGreen
    }

    /// Zvýraznění v editoru (temporary attributes – nejdou do textu ani do undo).
    static func apply(_ editor: NSTextView) {
        guard let lm = editor.layoutManager else { return }
        let all = NSRange(location: 0, length: (editor.string as NSString).length)
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: all)
        for tok in VarToken.scan(editor.string) {
            lm.addTemporaryAttribute(.foregroundColor, value: color(tok.kind), forCharacterRange: tok.range)
        }
    }

    /// Obarvený text pole mimo editaci.
    static func display(_ field: NSTextField) {
        let s = field.stringValue
        let tokens = VarToken.scan(s)
        let attr = NSMutableAttributedString(string: s, attributes: [
            .font: field.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.textColor,
        ])
        for tok in tokens { attr.addAttribute(.foregroundColor, value: color(tok.kind), range: tok.range) }
        if field.attributedStringValue != attr { field.attributedStringValue = attr }
    }
}
