import AppKit
import SwiftUI

private struct EnabledProbe: NSViewRepresentable {
    final class ProbeView: NSView { var contentEnabled = true }
    func makeNSView(context: Context) -> ProbeView { ProbeView() }
    func updateNSView(_ view: ProbeView, context: Context) { view.contentEnabled = context.environment.isEnabled }
}

@main
struct ScrollbarChecks {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        func content(_ selection: Int?, rows: Int, enabled: Bool = true) -> AnyView {
            AnyView(PaperScrollView(selectionID: selection) {
                VStack(alignment: .leading, spacing: 8) {
                    EnabledProbe().frame(height: 1)
                    ForEach(0..<rows, id: \.self) { index in
                        Text("Synthetic detail row \(index): enough text to wrap when the inspector becomes narrow.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }.disabled(!enabled))
        }
        let host = NSHostingView(rootView: content(1, rows: 40))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        try await settle(host)
        let scroll = find(host, as: OverlayScrollView.self)!
        assertOverlay(scroll)
        assert(scroll.documentView!.frame.height > scroll.contentView.bounds.height, "Long details must scroll")
        assert(abs(scroll.documentView!.frame.width - scroll.contentView.bounds.width) < 1,
               "The document follows the inspector width")
        assert(!scroll.hasHorizontalScroller)

        scroll.scrollerStyle = .legacy
        assert(scroll.scrollerStyle == .overlay, "System style assignments must not restore the legacy track")
        scroll.drawsBackground = true
        scroll.contentView.drawsBackground = true
        scroll.verticalScroller?.scrollerStyle = .legacy
        scroll.needsLayout = true
        try await settle(host)
        assertOverlay(scroll)

        NotificationCenter.default.post(name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
        try await settle(host)
        assertOverlay(scroll)
        let replacement = NSScroller(frame: NSRect(x: 0, y: 0, width: 16, height: 100))
        replacement.scrollerStyle = .legacy
        scroll.verticalScroller = replacement
        scroll.needsLayout = true
        try await settle(host)
        assertOverlay(scroll)

        scroll.contentView.scroll(to: NSPoint(x: 0, y: 120))
        scroll.reflectScrolledClipView(scroll.contentView)
        let offset = scroll.contentView.bounds.minY
        assert(offset > 80, "The fixture must be scrolled before testing refresh behavior")
        host.rootView = content(1, rows: 44, enabled: false)
        try await settle(host)
        assert(find(host, as: OverlayScrollView.self) === scroll, "Content updates keep the native scroll view")
        assert(abs(scroll.contentView.bounds.minY - offset) < 1, "Refreshing the same selection preserves scroll position")
        assert(find(host, as: EnabledProbe.ProbeView.self)?.contentEnabled == false,
               "Hosted details must inherit the parent disabled state")
        assertOverlay(scroll)

        host.rootView = content(2, rows: 44)
        try await settle(host)
        assert(abs(scroll.contentView.bounds.minY) < 1, "Selecting another item starts at the top")
        assert(find(host, as: EnabledProbe.ProbeView.self)?.contentEnabled == true)
        assertOverlay(scroll)

        window.setContentSize(NSSize(width: 280, height: 240))
        try await settle(host)
        assert(abs(scroll.documentView!.frame.width - scroll.contentView.bounds.width) < 1,
               "Resizing must not leave horizontal overflow")
        assertOverlay(scroll)
        host.rootView = content(3, rows: 1)
        try await settle(host)
        assert(scroll.documentView!.frame.height <= scroll.contentView.bounds.height + 1,
               "Short details must not retain the long document height")
        host.rootView = content(4, rows: 40)
        try await settle(host)
        assert(scroll.documentView!.frame.height > scroll.contentView.bounds.height)

        window.contentView = nil
        let nextWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 260),
                                  styleMask: [.titled], backing: .buffered, defer: false)
        nextWindow.contentView = host
        try await settle(host)
        assertOverlay(scroll)
        nextWindow.contentView = nil
        print("PASS: persistent overlay scrollbars, clear tracks, preference notifications, replacement, window moves, selection, sizing and disabled state")
    }

    @MainActor private static func assertOverlay(_ scroll: NSScrollView) {
        assert(scroll.scrollerStyle == .overlay)
        assert(scroll.verticalScroller?.scrollerStyle == .overlay)
        assert(!scroll.drawsBackground && !scroll.contentView.drawsBackground, "The track must stay transparent")
    }

    @MainActor private static func settle(_ host: NSView) async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        host.layoutSubtreeIfNeeded()
    }

    @MainActor private static func find<T: NSView>(_ node: NSView, as type: T.Type) -> T? {
        if let match = node as? T { return match }
        for child in node.subviews { if let match = find(child, as: type) { return match } }
        return nil
    }
}
