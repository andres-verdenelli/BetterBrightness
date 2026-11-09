import AppKit
import SwiftUI

/// An outline owns selection and insertion feedback; SwiftUI supplies row content and menus.
struct OrderedSidebar: NSViewRepresentable {
    let roots: [UUID]
    let children: [UUID: [UUID]]
    let selected: Set<UUID>
    let expanded: Set<UUID>
    let content: (UUID) -> AnyView
    let onSelect: (Set<UUID>) -> Void
    let onExpand: (Set<UUID>) -> Void
    let prepareDrag: () -> Bool
    let onMove: (Set<UUID>, UUID?, Int) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let outline = Outline()
        outline.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        outline.outlineTableColumn = outline.tableColumns[0]
        outline.headerView = nil
        outline.indentationPerLevel = 14
        outline.rowSizeStyle = .custom
        outline.usesAutomaticRowHeights = false
        outline.rowHeight = 44
        outline.intercellSpacing = NSSize(width: 0, height: 0)
        outline.backgroundColor = .clear
        outline.selectionHighlightStyle = .none
        outline.allowsMultipleSelection = true
        outline.allowsEmptySelection = true
        outline.autoresizesOutlineColumn = true
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outline.autosaveExpandedItems = false
        outline.registerForDraggedTypes([Coordinator.dragType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.setDraggingSourceOperationMask([], forLocal: false)
        outline.delegate = context.coordinator
        outline.dataSource = context.coordinator
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        context.coordinator.outline = outline
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(self)
    }
    final class Outline: NSOutlineView {
        // The trailing SwiftUI button is the only disclosure affordance.
        override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }
        override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
            var rect = super.frameOfCell(atColumn: column, row: row)
            let inset = CGFloat(max(0, level(forRow: row))) * 14 + 12
            rect.origin.x = inset
            rect.size.width = max(0, bounds.width - inset - 12)
            return rect
        }
    }
    final class Node: NSObject {
        let id: UUID
        init(_ id: UUID) { self.id = id }
    }
    final class Row: NSTableRowView {
        var member = false
        override func drawBackground(in dirtyRect: NSRect) {
            if isSelected {
                var rect = bounds.insetBy(dx: 8, dy: 3)
                if member { rect.origin.x += 14; rect.size.width -= 20 }
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
            }
        }
        override func drawSelection(in dirtyRect: NSRect) {}
    }
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        static let dragType = NSPasteboard.PasteboardType("andydev.BetterBrightness.sidebar-order")
        var owner: OrderedSidebar
        weak var outline: NSOutlineView?
        var nodes: [UUID: Node] = [:]
        var updating = false
        var dragging: Set<UUID> = []
        var dragParent: UUID?
        init(_ owner: OrderedSidebar) { self.owner = owner }
        func node(_ id: UUID) -> Node {
            if let node = nodes[id] { return node }
            let node = Node(id); nodes[id] = node; return node
        }
        func parent(_ id: UUID) -> UUID? { owner.children.first { $0.value.contains(id) }?.key }
        func update(_ next: OrderedSidebar) {
            guard let outline else { return }
            let structural = owner.roots != next.roots || owner.children != next.children || nodes.isEmpty
            owner = next
            updating = true
            outline.rowSizeStyle = .custom
            outline.usesAutomaticRowHeights = false
            outline.rowHeight = 44
            if structural { outline.reloadData() }
            for id in owner.roots where owner.children[id] != nil {
                if owner.expanded.contains(id) { outline.expandItem(node(id)) }
                else { outline.collapseItem(node(id)) }
            }
            outline.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<outline.numberOfRows))
            let indices = IndexSet(owner.selected.compactMap { id in
                let row = outline.row(forItem: node(id)); return row >= 0 ? row : nil
            })
            if outline.selectedRowIndexes != indices { outline.selectRowIndexes(indices, byExtendingSelection: false) }
            for row in 0..<outline.numberOfRows {
                guard let item = outline.item(atRow: row) as? Node else { continue }
                if let host = outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSHostingView<AnyView> {
                    host.rootView = owner.content(item.id)
                }
                if let view = outline.rowView(atRow: row, makeIfNecessary: true) as? Row { configure(view, item.id) }
            }
            updating = false
        }
        func configure(_ view: Row, _ id: UUID) {
            let p = parent(id)
            view.member = p != nil
            view.needsDisplay = true
        }
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if let item = item as? Node { return owner.children[item.id]?.count ?? 0 }
            return owner.roots.count
        }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            node((item as? Node).flatMap { owner.children[$0.id] }?[index] ?? owner.roots[index])
        }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? Node).map { owner.children[$0.id] != nil } ?? false }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? Node else { return nil }
            return NSHostingView(rootView: owner.content(item.id))
        }
        func outlineView(_ outlineView: NSOutlineView, heightOfItem item: Any) -> CGFloat { 44 }
        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            let row = Row(); if let item = item as? Node { configure(row, item.id) }; return row
        }
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let outline else { return }
            owner.onSelect(Set(outline.selectedRowIndexes.compactMap { (outline.item(atRow: $0) as? Node)?.id }))
        }
        func outlineViewItemDidExpand(_ notification: Notification) { expansionChanged() }
        func outlineViewItemDidCollapse(_ notification: Notification) { expansionChanged() }
        func expansionChanged() {
            guard !updating, let outline else { return }
            owner.onExpand(Set(owner.roots.filter { owner.children[$0] != nil && outline.isItemExpanded(node($0)) }))
        }
        func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool { updating || dragging.isEmpty }
        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let item = item as? Node else { return nil }
            let pb = NSPasteboardItem(); pb.setString(item.id.uuidString, forType: Self.dragType); return pb
        }
        func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
            dragging = Set(draggedItems.compactMap { ($0 as? Node)?.id })
            dragParent = dragging.first.flatMap(parent)
            if !owner.prepareDrag() { dragging = [] }
        }
        func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { dragging = []; dragParent = nil }
        /// Resolve root drops from the hovered row's root ancestor, not AppKit's
        /// proposed child container (which otherwise treats folder edges as entry).
        func destination(_ outline: NSOutlineView, info: NSDraggingInfo, item: Any?, index: Int) -> (UUID?, Int)? {
            guard info.draggingSource as? NSOutlineView === outline,
                  !dragging.isEmpty,
                  dragging.allSatisfy({ parent($0) == dragParent }) else { return nil }
            let point = outline.convert(info.draggingLocation, from: nil)
            let row = outline.row(at: point)
            if dragParent == nil {
                guard row >= 0, let hovered = outline.item(atRow: row) as? Node else {
                    return (nil, point.y < 0 ? 0 : owner.roots.count)
                }
                let root = parent(hovered.id) ?? hovered.id
                let header = outline.rect(ofRow: outline.row(forItem: node(root)))
                guard let insertion = SidebarOrder.rootInsertion(roots: owner.roots, children: owner.children,
                                                                hovered: hovered.id, afterHeader: point.y >= header.midY) else { return nil }
                return (nil, insertion)
            }
            if (item as? Node)?.id == dragParent, index >= 0,
               index <= (owner.children[dragParent!]?.count ?? 0) { return (dragParent, index) }
            guard row >= 0, let hovered = outline.item(atRow: row) as? Node,
                  let dragParent else { return nil }
            if hovered.id == dragParent { return (dragParent, 0) }
            guard parent(hovered.id) == dragParent,
                  let position = owner.children[dragParent]?.firstIndex(of: hovered.id) else { return nil }
            return (dragParent, position + (point.y >= outline.rect(ofRow: row).midY ? 1 : 0))
        }
        func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            guard let target = destination(outlineView, info: info, item: item, index: index) else { return [] }
            outlineView.setDropItem(target.0.map(node), dropChildIndex: target.1)
            return .move
        }
        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
            guard let target = destination(outlineView, info: info, item: item, index: index) else { return false }
            return owner.onMove(dragging, target.0, target.1)
        }
    }
}
