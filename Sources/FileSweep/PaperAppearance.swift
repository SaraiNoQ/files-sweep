import AppKit
import SwiftUI

enum PaperAppearance {
    static let background = NSColor(srgbRed: 238/255, green: 236/255, blue: 229/255, alpha: 1)
    static let ink = NSColor(srgbRed: 34/255, green: 42/255, blue: 44/255, alpha: 1)
    static let secondary = NSColor(srgbRed: 98/255, green: 104/255, blue: 106/255, alpha: 1)
    static let cinnabar = NSColor(srgbRed: 163/255, green: 50/255, blue: 47/255, alpha: 1)
    static let selection = NSColor(srgbRed: 224/255, green: 226/255, blue: 218/255, alpha: 1)
    static let paper = Color(nsColor: background)
    static let text = Color(nsColor: ink)
    static let muted = Color(nsColor: secondary)
    static let accent = Color(nsColor: cinnabar)
    static let gold = Color(red: 185/255, green: 145/255, blue: 73/255)
    static let line = text.opacity(0.12)
    static let mapColors: [(fill: Color, text: Color)] = [
        (accent, .white),
        (Color(red: 40/255, green: 71/255, blue: 80/255), .white),
        (Color(red: 70/255, green: 65/255, blue: 62/255), .white),
        (Color(red: 116/255, green: 98/255, blue: 73/255), .white),
        (Color(red: 167/255, green: 179/255, blue: 182/255), text),
        (Color(red: 195/255, green: 195/255, blue: 187/255), text)
    ]
}

struct PaperButtonStyle: ButtonStyle {
    var prominent = false
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, prominent: prominent, selected: selected)
    }

    private struct Content: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let selected: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovered = false

        var body: some View {
            configuration.label.font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 11).frame(height: 32)
                .foregroundStyle(prominent ? PaperAppearance.paper : PaperAppearance.text)
                .background(GlassSurface(shape: RoundedRectangle(cornerRadius: 10),
                    tint: prominent ? (hovered && enabled ? PaperAppearance.accent : PaperAppearance.text) : nil))
                .overlay(RoundedRectangle(cornerRadius: 10).fill(PaperAppearance.text.opacity(configuration.isPressed ? 0.08 : 0)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? PaperAppearance.accent : .clear, lineWidth: 1.5))
                .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.97 : 1)
                .offset(y: reduceMotion ? 0 : configuration.isPressed ? 1 : hovered && enabled ? -1 : 0)
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
                .opacity(enabled ? 1 : 0.4).onHover { hovered = $0 }
        }
    }
}

/// Opaque color and highlights preserve the glass finish without nested backdrop filters.
struct GlassSurface<S: InsettableShape>: View {
    let shape: S
    var tint: Color?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            shape.fill(tint ?? PaperAppearance.paper)
            shape.fill(LinearGradient(colors: [.white.opacity(tint == nil ? 0.22 : 0.1), .clear],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.85), PaperAppearance.text.opacity(contrast == .increased ? 0.6 : 0.16)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct GlassPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.98 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// The marker lives inside scroll content, so it only styles its own scroll view.
struct TransparentScrollbars: NSViewRepresentable {
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) { view.configureAfterLayout() }

    final class Marker: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureAfterLayout()
        }
        func configureAfterLayout() {
            DispatchQueue.main.async { [weak self] in
                guard let scroll = self?.enclosingScrollView else { return }
                if scroll.scrollerStyle != .overlay { scroll.scrollerStyle = .overlay }
                if let bar = scroll.verticalScroller, bar.scrollerStyle != .overlay { bar.scrollerStyle = .overlay }
                if let bar = scroll.horizontalScroller, bar.scrollerStyle != .overlay { bar.scrollerStyle = .overlay }
                if scroll.drawsBackground { scroll.drawsBackground = false }
                if scroll.contentView.drawsBackground { scroll.contentView.drawsBackground = false }
                scroll.setAccessibilityIdentifier("FileSweep.transparent.\(scroll.scrollerStyle.rawValue).\(scroll.verticalScroller?.scrollerStyle.rawValue ?? -1)")
            }
        }
    }
}
