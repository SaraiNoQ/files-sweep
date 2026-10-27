import AppKit
import SwiftUI
import FileSweepCore

/// AppKit recycles rows; only expanded branches get item objects and sorted children.
struct FileOutline: NSViewRepresentable {
    let snapshot: ScanSnapshot
    let searchResults: [Int]?
    let findings: [Int: DeveloperFinding]
    let revision: Int
    var rootID: Int = 0
    let selection: Int?
    let onSelect: (Int) -> Void
    let onOpen: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = OutlineScrollView()
        let outline = DirectoryOutlineView()
        outline.style = .plain
        for (identifier, title, width) in [("name", "名称", 210.0), ("size", "逻辑大小", 104.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title; column.width = width
            outline.addTableColumn(column)
        }
        outline.outlineTableColumn = outline.tableColumns[0]
        outline.rowHeight = 44
        outline.headerView = nil
        outline.backgroundColor = .clear
        outline.intercellSpacing = .zero
        outline.indentationPerLevel = 18
        scroll.backgroundColor = PaperAppearance.background
        scroll.appearance = NSAppearance(named: .aqua)
        outline.columnAutoresizingStyle = .noColumnAutoresizing
        outline.tableColumns[0].minWidth = 1
        outline.tableColumns[1].minWidth = 104
        outline.tableColumns[1].maxWidth = 104
        for column in outline.tableColumns { column.resizingMask = [] }
        outline.autoresizingMask = []
        outline.usesAlternatingRowBackgroundColors = false
        outline.allowsMultipleSelection = false
        outline.delegate = context.coordinator
        outline.dataSource = context.coordinator
        outline.target = context.coordinator
        outline.doubleAction = #selector(Coordinator.openItem(_:))
        outline.setAccessibilityLabel("文件目录树")
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        // Reserve a gutter so the scroller can never obscure the size column.
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = false
        scroll.hasHorizontalScroller = false
        return scroll
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        guard let outline = view.documentView as? NSOutlineView else { return }
        let coordinator = context.coordinator
        coordinator.settingSelection = true
        defer { coordinator.settingSelection = false }
        coordinator.parent = self
        let rowHeight: CGFloat = searchResults == nil ? 44 : 54
        if outline.rowHeight != rowHeight { outline.rowHeight = rowHeight }
        let reloaded = coordinator.revision != revision || coordinator.generation != snapshot.generation || coordinator.rootID != rootID
            || coordinator.results != searchResults
        if reloaded {
            coordinator.generation = snapshot.generation
            coordinator.revision = revision
            coordinator.rootID = rootID
            coordinator.results = searchResults
            coordinator.items.removeAll(); coordinator.sortedChildren.removeAll()
            outline.reloadData()
            if searchResults == nil { outline.expandItem(coordinator.item(for: rootID)) }
        }
        guard reloaded || coordinator.selection != selection else { return }
        coordinator.selection = selection
        if let selection, snapshot.entries.indices.contains(selection) {
            if searchResults == nil {
                var ancestors: [Int] = []
                var parent = snapshot.entries[selection].parent
                while let id = parent {
                    ancestors.append(id)
                    if id == rootID { break }
                    parent = snapshot.entries[id].parent
                }
                for id in ancestors.reversed() { outline.expandItem(coordinator.item(for: id)) }
            }
            let item = coordinator.item(for: selection)
            let row = outline.row(forItem: item)
            if row >= 0 && row != outline.selectedRow {
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outline.scrollRowToVisible(row)
            } else if row < 0 {
                outline.deselectAll(nil)
            }
        } else if outline.selectedRow >= 0 {
            outline.deselectAll(nil)
        }
    }

    final class DirectoryOutlineView: NSOutlineView {
        override func frameOfOutlineCell(atRow row: Int) -> NSRect {
            let frame = super.frameOfOutlineCell(atRow: row)
            return frame.isEmpty ? frame : frame.offsetBy(dx: 12, dy: 0)
        }
        override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
            var frame = super.frameOfCell(atColumn: column, row: row)
            if column == 0 { frame.origin.x += 12; frame.size.width = max(0, frame.width - 12) }
            return frame
        }
    }

    final class Item: NSObject { let id: Int; init(_ id: Int) { self.id = id } }

    final class OutlineScrollView: NSScrollView {
        override var scrollerStyle: NSScroller.Style {
            get { super.scrollerStyle }
            set { super.scrollerStyle = .overlay }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scrollerStyle = .overlay
        }

        override func layout() {
            super.layout()
            if let scroller = verticalScroller, scroller.scrollerStyle != .overlay { scroller.scrollerStyle = .overlay }
            setAccessibilityIdentifier("FileSweep.directory.\(scrollerStyle.rawValue).\(verticalScroller?.scrollerStyle.rawValue ?? -1)")
            guard let outline = documentView as? NSOutlineView, outline.tableColumns.count == 2 else { return }
            let width = contentView.bounds.width - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay)
            guard width > 0 else { return }
            if abs(outline.frame.width - width) > 0.5 { outline.setFrameSize(NSSize(width: width, height: outline.frame.height)) }
            let nameWidth = max(1, width - outline.tableColumns[1].width)
            if abs(outline.tableColumns[0].width - nameWidth) > 0.5 { outline.tableColumns[0].width = nameWidth }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: FileOutline
        var revision = -1
        var rootID = -1
        var results: [Int]?
        var generation: UUID?
        var selection: Int?
        var items: [Int: Item] = [:]
        var sortedChildren: [Int: [Int]] = [:]
        var settingSelection = false
        init(_ parent: FileOutline) { self.parent = parent }

        func item(for id: Int) -> Item {
            if let existing = items[id] { return existing }
            let result = Item(id); items[id] = result; return result
        }

        func children(_ item: Any?) -> [Int] {
            if parent.searchResults != nil { return item == nil ? parent.searchResults! : [] }
            guard let item = item as? Item else {
                return parent.snapshot.entries.indices.contains(parent.rootID) ? [parent.rootID] : []
            }
            guard parent.snapshot.entries.indices.contains(item.id) else { return [] }
            if let cached = sortedChildren[item.id] { return cached }
            let ids = parent.snapshot.children(of: item.id).sorted {
                let a = parent.snapshot.entries[$0], b = parent.snapshot.entries[$1]
                return a.logicalBytes == b.logicalBytes ? a.name.localizedStandardCompare(b.name) == .orderedAscending : a.logicalBytes > b.logicalBytes
            }
            sortedChildren[item.id] = ids
            return ids
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { children(item).count }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            let ids = children(item)
            guard ids.indices.contains(index) else { return Item(-1) }
            let id = ids[index]
            return self.item(for: id)
        }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard parent.searchResults == nil, let item = item as? Item else { return false }
            guard parent.snapshot.entries.indices.contains(item.id) else { return false }
            return parent.snapshot.entries[item.id].firstChild != nil
        }
        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            PaperRow()
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? Item, let column = tableColumn else { return nil }
            guard parent.snapshot.entries.indices.contains(item.id) else { return nil }
            let entry = parent.snapshot.entries[item.id]
            let finding = parent.findings[item.id]
            if column.identifier.rawValue == "name" {
                let cell = (outlineView.makeView(withIdentifier: column.identifier, owner: self) as? NameCell) ?? NameCell()
                cell.identifier = column.identifier
                cell.textField?.stringValue = entry.name
                cell.textField?.font = .systemFont(ofSize: 14, weight: entry.kind == .directory ? .medium : .regular)
                cell.detailField.isHidden = parent.searchResults == nil
                if parent.searchResults != nil {
                    let parentURL = parent.snapshot.url(for: item.id).deletingLastPathComponent()
                    let root = parent.snapshot.root.path
                    let path = parentURL.path.hasPrefix(root + "/") ? String(parentURL.path.dropFirst(root.count + 1)) : parentURL.lastPathComponent
                    cell.detailField.stringValue = finding.map { "\($0.ecosystem.rawValue) · \(path)" } ?? path
                }
                let protected = finding != nil && (finding?.isProtected == true || parent.snapshot.isStale)
                let symbol = protected ? "lock.shield" : entry.kind == .directory ? "folder" : entry.kind == .symbolicLink ? "link" : "doc"
                cell.imageView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: protected ? "受保护" : nil)
                cell.toolTip = parent.snapshot.url(for: item.id).path + (finding.map { "\n\($0.ecosystem.rawValue) · \($0.kind.rawValue) · \($0.isProtected ? "受保护" : "待核验")" } ?? "")
                return cell
            }
            let cell = (outlineView.makeView(withIdentifier: column.identifier, owner: self) as? SizeCell) ?? SizeCell()
            cell.identifier = column.identifier
            cell.textField?.stringValue = formatBytes(entry.logicalBytes) + (entry.incomplete ? "+" : "")
            return cell
        }
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !settingSelection, let view = notification.object as? NSOutlineView,
                  let item = view.item(atRow: view.selectedRow) as? Item else { return }
            guard parent.snapshot.entries.indices.contains(item.id) else { return }
            parent.onSelect(item.id)
        }
        @objc func openItem(_ sender: NSOutlineView) {
            if let item = sender.item(atRow: sender.clickedRow) as? Item { parent.onOpen(item.id) }
        }
    }

    final class PaperRow: NSTableRowView {
        private var hoverTracking: NSTrackingArea?
        private var hovered = false
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            guard hoverTracking == nil else { return }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
            addTrackingArea(area); hoverTracking = area
        }
        override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
        override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
        override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
        override func drawBackground(in dirtyRect: NSRect) {
            super.drawBackground(in: dirtyRect)
            if !isSelected {
                if hovered {
                    let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 3), xRadius: 9, yRadius: 9)
                    NSGradient(starting: .white.withAlphaComponent(0.6), ending: PaperAppearance.selection.withAlphaComponent(0.45))?.draw(in: shape, angle: 90)
                }
                PaperAppearance.ink.withAlphaComponent(0.07).setStroke()
                let line = NSBezierPath()
                line.move(to: NSPoint(x: 24, y: bounds.maxY - 0.5))
                line.line(to: NSPoint(x: bounds.maxX - 12, y: bounds.maxY - 0.5))
                line.lineWidth = 0.5
                line.stroke()
            }
        }
        override func drawSelection(in dirtyRect: NSRect) {
            let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 3), xRadius: 9, yRadius: 9)
            PaperAppearance.selection.setFill(); shape.fill()
            NSGradient(starting: PaperAppearance.selection, ending: .white.withAlphaComponent(0.85))?.draw(in: shape, angle: 90)
            let increasedContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            (increasedContrast ? PaperAppearance.cinnabar : .white.withAlphaComponent(0.9)).setStroke()
            shape.lineWidth = increasedContrast ? 1.5 : 0.5
            shape.stroke()
        }
    }

    final class NameCell: NSTableCellView {
        let detailField = NSTextField(labelWithString: "")
        init() {
            super.init(frame: .zero)
            let icon = NSImageView()
            icon.contentTintColor = PaperAppearance.cinnabar
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingMiddle
            label.font = .systemFont(ofSize: 14)
            label.textColor = PaperAppearance.ink
            detailField.font = .systemFont(ofSize: 12)
            detailField.textColor = PaperAppearance.secondary
            detailField.lineBreakMode = .byTruncatingMiddle
            let stack = NSStackView(views: [label, detailField])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 2
            imageView = icon; textField = label
            for view in [icon, stack] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: leadingAnchor),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 20), icon.heightAnchor.constraint(equalToConstant: 20),
                stack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
                stack.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.widthAnchor.constraint(equalTo: stack.widthAnchor),
                detailField.widthAnchor.constraint(equalTo: stack.widthAnchor)
            ])
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    }

    final class SizeCell: NSTableCellView {
        init() {
            super.init(frame: .zero)
            let label = NSTextField(labelWithString: "")
            label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            label.textColor = PaperAppearance.ink
            label.alignment = .right
            label.translatesAutoresizingMaskIntoConstraints = false
            textField = label
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                label.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    }
}
