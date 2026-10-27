import AppKit
import SwiftUI
import FileSweepCore

@main
struct OutlineChecks {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".bench-fixture/outline-check-\(UUID())")
        let folder = root.appendingPathComponent("Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["A", "B"] { try Data(count: 1).write(to: folder.appendingPathComponent(name)) }
        let snapshot = try FileScanner.scan(root: root)
        let files = snapshot.entries.filter { $0.kind == .file }.map(\.id)
        func content(_ selection: Int?, results: [Int]? = nil) -> FileOutline {
            FileOutline(snapshot: snapshot, searchResults: results, findings: [:], revision: 0,
                        selection: selection, onSelect: { _ in }, onOpen: { _ in })
        }
        let host = NSHostingView(rootView: content(files[0]))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        func findOutline(_ node: NSView) -> NSOutlineView? {
            if let outline = node as? NSOutlineView { return outline }
            for child in node.subviews { if let outline = findOutline(child) { return outline } }
            return nil
        }
        let outline = findOutline(host)!
        let rootItem = outline.item(atRow: 0)!
        assert(outline.frameOfOutlineCell(atRow: 0).minX >= 12)
        let sizeFrame = outline.frameOfCell(atColumn: 1, row: 0)
        assert(sizeFrame.width == 104, "left inset must not shrink the size column")
        assert(outline.numberOfRows == 4)
        outline.collapseItem(rootItem)
        host.rootView = content(files[0])
        try await Task.sleep(for: .milliseconds(50))
        host.layoutSubtreeIfNeeded()
        assert(!outline.isItemExpanded(rootItem), "unrelated view updates must not reopen collapsed ancestors")
        host.rootView = content(files[1])
        try await Task.sleep(for: .milliseconds(50))
        host.layoutSubtreeIfNeeded()
        assert(outline.isItemExpanded(rootItem) && outline.selectedRow >= 0)
        host.rootView = content(nil)
        try await Task.sleep(for: .milliseconds(50))
        assert(outline.selectedRow == -1)
        host.rootView = content(files[0], results: [files[0]])
        try await Task.sleep(for: .milliseconds(50))
        assert(outline.numberOfRows == 1 && outline.selectedRow == 0)
        host.rootView = content(files[1], results: [files[1]])
        try await Task.sleep(for: .milliseconds(50))
        assert((outline.item(atRow: 0) as? FileOutline.Item)?.id == files[1])
        let row = FileOutline.PaperRow(frame: .zero)
        row.updateTrackingAreas(); row.updateTrackingAreas()
        assert(row.trackingAreas.count == 1)
        window.contentView = nil
        print("PASS: outline inset, size column, stable collapse, selection, result replacement and tracking reuse")
    }
}
