import AppKit
import MinorRESTCore
import SwiftUI

/// Strom projektu nad `NSOutlineView` (source list, jeden sloupec). Stav drží `TreeStore`,
/// view se znovu načte při změně `version`.
struct TreeOutlineView: NSViewRepresentable {
    let store: TreeStore
    let version: Int
    let pendingEdit: String?
    let font: NSFont

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = TreeOutline()
        outline.coordinator = context.coordinator
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .custom
        outline.floatsGroupRows = false
        outline.allowsEmptySelection = true
        outline.autoresizesOutlineColumn = false
        let column = NSTableColumn(identifier: .init("name"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        context.coordinator.outline = outline

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.font = font
        if c.version != version {
            c.version = version
            c.reload()
        }
        if let rel = pendingEdit {
            DispatchQueue.main.async { if c.store.pendingEdit == rel { c.beginEditing(rel) } }
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate {
        let store: TreeStore
        weak var outline: TreeOutline?
        var version = -1
        var font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        private var root: TreeItem?
        private var restoring = false
        private var editingRel: String?
        private var editCancelled = false

        init(store: TreeStore) { self.store = store }

        /// Nový strom z `store.root`, obnova rozbalení z workspace a výběru.
        func reload() {
            guard let outline else { return }
            root = store.root.map(TreeItem.init)
            restoring = true
            outline.reloadData()
            let expanded = store.expanded
            for rel in expanded.sorted() {
                if let item = item(rel), outline.row(forItem: item) >= 0 { outline.expandItem(item) }
            }
            restoring = false
            select(store.selection)
        }

        func item(_ rel: String) -> TreeItem? { root?.find(rel) }

        private func select(_ rel: String?) {
            guard let outline else { return }
            guard let rel, let item = item(rel), case let row = outline.row(forItem: item), row >= 0 else {
                outline.deselectAll(nil)
                return
            }
            outline.selectRowIndexes([row], byExtendingSelection: false)
            outline.scrollRowToVisible(row)
        }

        var selectedRel: String? {
            guard let outline, outline.selectedRow >= 0 else { return nil }
            return (outline.item(atRow: outline.selectedRow) as? TreeItem)?.node.rel
        }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            ((item as? TreeItem) ?? root)?.children.count ?? 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            ((item as? TreeItem) ?? root)!.children[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let i = item as? TreeItem else { return false }
            return i.node.kind == .folder && i.node.error.isEmpty
        }

        // MARK: Delegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let i = item as? TreeItem else { return nil }
            let id = NSUserInterfaceItemIdentifier("cell")
            let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? TreeCellView ?? TreeCellView(id: id)
            cell.configure(i.node, font: font)
            cell.textField?.delegate = self
            return cell
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            ceil(font.boundingRectForFont.height) + 6
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !restoring else { return }
            store.selection = selectedRel
        }

        func outlineViewItemDidExpand(_ notification: Notification) { expandChanged(notification, true) }
        func outlineViewItemDidCollapse(_ notification: Notification) { expandChanged(notification, false) }

        private func expandChanged(_ notification: Notification, _ on: Bool) {
            guard !restoring, let i = notification.userInfo?["NSObject"] as? TreeItem else { return }
            store.setExpanded(i.node.rel, on)
        }

        // MARK: Klávesy a menu

        func toggle(_ rel: String?) {
            guard let outline, let rel, let item = item(rel), item.node.kind == .folder else { return }
            if outline.isItemExpanded(item) { outline.collapseItem(item) } else { outline.expandItem(item) }
        }

        func menu(for rel: String?) -> NSMenu {
            let menu = NSMenu()
            func add(_ key: String, _ action: @escaping @MainActor () -> Void) {
                menu.addItem(ActionMenuItem(title: t(key), action: action))
            }
            add("tree.newRequest") { [store] in Task { await store.createRequest(near: rel) } }
            add("tree.newFolder") { [store] in Task { await store.createFolder(near: rel) } }
            guard let rel else { return menu }
            menu.addItem(.separator())
            add("tree.rename") { [weak self] in self?.beginEditing(rel) }
            add("tree.duplicate") { [store] in Task { await store.duplicate(rel) } }
            menu.addItem(.separator())
            add("tree.reveal") { [store] in Task { await store.reveal(rel) } }
            menu.addItem(.separator())
            add("tree.delete") { [store] in Task { await store.delete(rel) } }
            return menu
        }

        // MARK: Inline přejmenování

        func beginEditing(_ rel: String) {
            guard let outline, let item = item(rel), item.node.error.isEmpty else { return }
            if store.pendingEdit == rel { store.pendingEdit = nil }
            let row = outline.row(forItem: item)
            guard row >= 0, let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? TreeCellView,
                  let field = cell.textField else { return }
            outline.scrollRowToVisible(row)
            editingRel = rel
            editCancelled = false
            field.isEditable = true
            outline.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            editCancelled = true
            outline?.window?.makeFirstResponder(outline)
            return true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField, let rel = editingRel,
                  let node = item(rel)?.node else { return }
            editingRel = nil
            field.isEditable = false
            let name = field.stringValue
            field.stringValue = node.name
            if outline?.window?.firstResponder !== outline { outline?.window?.makeFirstResponder(outline) }
            guard !editCancelled else { return }
            Task { await store.rename(rel, to: name) }
        }
    }
}

// MARK: - Položky a buňky

/// Referenční obal uzlu (NSOutlineView porovnává položky podle identity).
final class TreeItem: NSObject {
    let node: TreeNode
    let children: [TreeItem]

    init(_ node: TreeNode) {
        self.node = node
        children = node.children.map(TreeItem.init)
    }

    func find(_ rel: String) -> TreeItem? {
        if node.rel == rel { return self }
        for c in children {
            if let hit = c.find(rel) { return hit }
        }
        return nil
    }
}

final class TreeCellView: NSTableCellView {
    private let icon = NSImageView()
    private let badge = NSTextField(labelWithString: "")
    private var badgeWidth: NSLayoutConstraint!

    init(id: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        identifier = id
        let name = NSTextField(labelWithString: "")
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField = name
        badge.alignment = .left
        icon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        for v in [icon, badge, name] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        badgeWidth = badge.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeWidth,
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
        ])
        nameLeading = name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5)
        nameLeading.isActive = true
    }

    private var nameLeading: NSLayoutConstraint!

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ node: TreeNode, font: NSFont) {
        guard let name = textField else { return }
        name.font = font
        name.stringValue = node.name
        name.isEditable = false
        let folder = node.kind == .folder
        icon.isHidden = !folder
        badge.isHidden = folder
        nameLeading.isActive = false
        if folder {
            nameLeading = name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5)
        } else {
            let badgeFont = NSFont.monospacedSystemFont(ofSize: max(font.pointSize - 3, 9), weight: .semibold)
            badge.font = badgeFont
            badge.stringValue = node.method
            badge.textColor = Self.methodColor(node.method)
            badgeWidth.constant = ceil(("OPTIONS" as NSString).size(withAttributes: [.font: badgeFont]).width) + 2
            nameLeading = name.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 4)
        }
        nameLeading.isActive = true
        let broken = !node.error.isEmpty
        name.textColor = broken ? .tertiaryLabelColor : .labelColor
        toolTip = broken ? errorText(code: node.error) : nil
    }

    static func methodColor(_ method: String) -> NSColor {
        NSColor(named: "Method" + method.lowercased().capitalized) ?? .secondaryLabelColor
    }
}

/// Outline s klávesami: Enter = rozbalit/sbalit, F2 = přejmenovat, Cmd+Backspace/Delete = smazat.
final class TreeOutline: NSOutlineView {
    weak var coordinator: TreeOutlineView.Coordinator?

    override func keyDown(with event: NSEvent) {
        guard let c = coordinator else { return super.keyDown(with: event) }
        let rel = c.selectedRel
        let cmd = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 36, 76: c.toggle(rel)                                     // Return, Enter
        case 120: if let rel, !rel.isEmpty { c.beginEditing(rel) }     // F2
        case 51 where cmd, 117: Task { await c.store.delete(rel) }     // Cmd+Backspace, Delete (fwd)
        default: super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let c = coordinator else { return nil }
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 { selectRowIndexes([row], byExtendingSelection: false) } else { deselectAll(nil) }
        return c.menu(for: row >= 0 ? (item(atRow: row) as? TreeItem)?.node.rel : nil)
    }
}

/// Položka menu s closure místo target/action.
@MainActor final class ActionMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, action: @escaping @MainActor () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}
