import AppKit
import SwiftUI

/// Strom projektu nad `NSOutlineView` (source list, jeden sloupec). Stav drží `TreeStore`,
/// view se znovu načte při změně `version` nebo filtru.
struct TreeOutlineView: NSViewRepresentable {
    let store: TreeStore
    let version: Int
    let query: String
    let pendingEdit: String?
    let focusRequest: Int
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
        outline.registerForDraggedTypes([.treeRel])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.target = context.coordinator
        outline.doubleAction = #selector(Coordinator.doubleClicked)
        context.coordinator.outline = outline

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let cur = context.coordinator
        cur.font = font
        if cur.version != version || cur.query != query {
            cur.version = version
            cur.query = query
            cur.reload()
        }
        if cur.focusRequest != focusRequest {
            cur.focusRequest = focusRequest
            cur.focusTree()
        }
        if let rel = pendingEdit {
            DispatchQueue.main.async { if cur.store.pendingEdit == rel { cur.beginEditing(rel) } }
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate {
        let store: TreeStore
        weak var outline: TreeOutline?
        var version = -1
        var query = ""
        var focusRequest = 0
        private var pendingDrop: PendingDrop?
        var font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        private var root: TreeItem?
        private var restoring = false
        private var editingRel: String? {
            didSet { store.editing = editingRel != nil }
        }
        private var editCancelled = false

        init(store: TreeStore) { self.store = store }

        /// Nový strom z `store.visibleRoot`, rozbalení z workspace (při filtru vše) a obnova výběru.
        func reload() {
            guard let outline else { return }
            root = store.visibleRoot.map(TreeItem.init)
            restoring = true
            outline.reloadData()
            if store.filtering {
                outline.expandItem(nil, expandChildren: true)
            } else {
                for rel in store.expanded.sorted() {
                    if let item = item(rel), outline.row(forItem: item) >= 0 { outline.expandItem(item) }
                }
            }
            restoring = false
            select(store.selection)
        }

        func focusTree() {
            select(store.selection)
            outline?.window?.makeFirstResponder(outline)
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
            ((item as? TreeItem) ?? root)?.children[index] ?? NSNull()
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
            guard !restoring, !store.filtering, let i = notification.userInfo?["NSObject"] as? TreeItem else { return }
            store.setExpanded(i.node.rel, on)
        }

        // MARK: Drag & drop

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard !store.filtering, editingRel == nil, let i = item as? TreeItem else { return nil }
            let pb = NSPasteboardItem()
            pb.setString(i.node.rel, forType: .treeRel)
            return pb
        }

        /// Návrh `NSOutlineView` (rodič + index mezi dětmi, -1 = na položku) převede na pravidla stromu:
        /// request na složku = dovnitř, request na request = za něj, složka na request = do jeho složky,
        /// složky jen mezi složky a requesty jen mezi requesty, složka ne do sebe.
        func outlineView(
            _ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?,
            proposedChildIndex index: Int
        ) -> NSDragOperation {
            pendingDrop = nil
            guard !store.filtering, let rel = info.draggingPasteboard.string(forType: .treeRel),
                let dragged = store.node(rel), let root
            else { return [] }
            var target = item as? TreeItem
            var child: Int? = index < 0 ? nil : index
            if let txt = target, txt.node.kind == .request {
                let parent = outlineView.parent(forItem: txt) as? TreeItem
                target = parent
                child =
                    dragged.kind == .request ? (parent ?? root).children.firstIndex { $0 === txt }.map { $0 + 1 } : nil
            }
            let parent = target ?? root
            let folders = parent.children.filter { $0.node.kind == .folder }.count
            if let cur = child {
                child = dragged.kind == .folder ? min(cur, folders) : max(cur, folders)
            }
            let dest = parent.node.rel
            if dragged.kind == .folder && (dest == rel || dest.hasPrefix(rel + "/")) { return [] }
            guard let moveIndex = parent.node.moveIndex(of: dragged, before: child) else { return [] }
            outlineView.setDropItem(target, dropChildIndex: child ?? NSOutlineViewDropOnItemIndex)
            pendingDrop = PendingDrop(rel: rel, parent: dest, index: moveIndex)
            return .move
        }

        func outlineView(
            _ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?,
            childIndex index: Int
        ) -> Bool {
            guard let drop = pendingDrop else { return false }
            pendingDrop = nil
            Task { await store.move(drop.rel, to: drop.parent, index: drop.index) }
            return true
        }

        // MARK: Klávesy a menu

        @objc func doubleClicked() {
            guard let outline, outline.clickedRow >= 0,
                let i = outline.item(atRow: outline.clickedRow) as? TreeItem
            else { return }
            if i.node.kind == .request { Task { await store.open(i.node.rel) } } else { toggle(i.node.rel) }
        }

        /// Enter: složku rozbalí/sbalí, request otevře v tabu.
        func activate(_ rel: String?) {
            guard let rel, let i = item(rel) else { return }
            if i.node.kind == .request { Task { await store.open(rel) } } else { toggle(rel) }
        }

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
            if store.root?.find(rel)?.kind == .request {
                add("tree.copyCurl") { [store] in store.onCopyCurl?(rel) }
            }
            menu.addItem(.separator())
            if let node = store.root?.find(rel), node.kind == .folder {
                add("tree.settings") { [store] in store.openSettings(rel) }
            }
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
                let field = cell.textField
            else { return }
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
                let node = item(rel)?.node
            else { return }
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
        for cur in children {
            if let hit = cur.find(rel) { return hit }
        }
        return nil
    }
}

final class TreeCellView: NSTableCellView {
    private let icon = NSImageView()
    private let badge = NSTextField(labelWithString: "")
    private var badgeWidth = NSLayoutConstraint()

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
        for val in [icon, badge, name] as [NSView] {
            val.translatesAutoresizingMaskIntoConstraints = false
            addSubview(val)
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
            name.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4)
        ])
        nameLeading = name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5)
        nameLeading.isActive = true
    }

    private var nameLeading = NSLayoutConstraint()

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

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

/// Outline s klávesami: Enter = rozbalit/sbalit složku, otevřít request, F2 = přejmenovat,
/// Cmd+Backspace/Delete = smazat.
final class TreeOutline: NSOutlineView {
    weak var coordinator: TreeOutlineView.Coordinator?

    override func keyDown(with event: NSEvent) {
        guard let cur = coordinator else { return super.keyDown(with: event) }
        let rel = cur.selectedRel
        let cmd = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 36, 76: cur.activate(rel)  // Return, Enter
        case 120: if let rel, !rel.isEmpty { cur.beginEditing(rel) }  // F2
        case 51 where cmd, 117: Task { await cur.store.delete(rel) }  // Cmd+Backspace, Delete (fwd)
        default: super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let cur = coordinator else { return nil }
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 { selectRowIndexes([row], byExtendingSelection: false) } else { deselectAll(nil) }
        return cur.menu(for: row >= 0 ? (item(atRow: row) as? TreeItem)?.node.rel : nil)
    }
}

extension NSPasteboard.PasteboardType {
    static let treeRel = NSPasteboard.PasteboardType("cz.novami.minor.rest.tree-rel")
}

/// Položka menu s closure místo target/action.
nonisolated final class ActionMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, action: @escaping @MainActor () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @MainActor @objc private func run() { handler() }
}

/// Cíl právě probíhajícího přetažení v outline.
private struct PendingDrop {
    let rel: String
    let parent: String
    let index: Int
}
