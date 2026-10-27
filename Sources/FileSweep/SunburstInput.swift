import AppKit
import SwiftUI
import FileSweepCore

struct SunburstInput: NSViewRepresentable {
    let key: String
    let sectors: [SunburstSector]
    let ready: Bool
    let selection: Int?
    let onSelect: (Int) -> Void
    let onActivate: (Int) -> Void
    let onHover: (Int?) -> Void
    let onPreview: (Int?) -> Void
    let onBack: () -> Void
    @Environment(\.isEnabled) private var enabled

    func makeNSView(context: Context) -> SunburstInputView { SunburstInputView() }
    func updateNSView(_ view: SunburstInputView, context: Context) {
        view.configure(key: key, sectors: sectors, selection: selection, enabled: enabled && ready)
        view.onSelect = onSelect; view.onActivate = onActivate
        view.onHover = onHover; view.onPreview = onPreview; view.onBack = onBack
    }
}

/// One native event surface avoids overlapping full-size SwiftUI buttons intercepting arcs.
final class SunburstInputView: NSView {
    private(set) var key = ""
    private(set) var sectors: [SunburstSector] = []
    private(set) var enabled = true
    private var activeID: Int?
    private var lastSelection: Int?
    private var hoveredID: Int?
    private var lastPress: (key: String, hit: SunburstHit?)?
    private var previewing = false
    private var tracking: NSTrackingArea?
    var onSelect: (Int) -> Void = { _ in }
    var onActivate: (Int) -> Void = { _ in }
    var onHover: (Int?) -> Void = { _ in }
    var onPreview: (Int?) -> Void = { _ in }
    var onBack: () -> Void = {}

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(key: String, sectors: [SunburstSector], selection: Int?, enabled: Bool) {
        if self.key != key {
            activeID = nil; hoveredID = nil; previewing = false; lastSelection = nil
        }
        self.key = key; self.sectors = sectors; self.enabled = enabled
        if lastSelection != selection || activeID == nil {
            activeID = sectors.first(where: { $0.entryID != nil && $0.entryID == selection })?.id
            lastSelection = selection
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard tracking == nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }

    override func mouseDown(with event: NSEvent) {
        guard enabled else { return }
        window?.makeFirstResponder(self)
        let hit = Sunburst.hitTest(convert(event.locationInWindow, from: nil), size: bounds.size, sectors: sectors)
        if event.clickCount > 1 {
            guard lastPress?.key == key, lastPress?.hit == hit else { return }
            if case let .sector(id) = hit { onActivate(id) }
            return
        }
        lastPress = (key, hit)
        switch hit {
        case .center: activeID = nil; onBack()
        case .sector(let id): activeID = id; onSelect(id)
        case nil: break
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard enabled else { return }
        let hit = Sunburst.hitTest(convert(event.locationInWindow, from: nil), size: bounds.size, sectors: sectors)
        let id: Int? = if case let .sector(id) = hit { id } else { nil }
        if id != hoveredID { hoveredID = id; onHover(id) }
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { hoveredID = nil; onHover(nil) }

    override func keyDown(with event: NSEvent) {
        guard enabled else { return }
        switch event.keyCode {
        case 123, 124, 125, 126:
            guard !sectors.isEmpty else { return }
            let forward = event.keyCode == 124 || event.keyCode == 125
            let current = sectors.firstIndex { $0.id == activeID }
            let index = current.map { ($0 + (forward ? 1 : sectors.count - 1)) % sectors.count } ?? (forward ? 0 : sectors.count - 1)
            activeID = sectors[index].id
            hoveredID = sectors[index].id; onHover(sectors[index].id)
            if sectors[index].entryID != nil { onSelect(sectors[index].id) }
        case 36, 76:
            if let activeID { onActivate(activeID) } else { onBack() }
        case 49:
            if !event.isARepeat, let activeID { previewing = true; onPreview(activeID) }
        case 53:
            previewing = false; onPreview(nil)
        case 51, 117:
            previewing = false; onPreview(nil); onBack()
        default: super.keyDown(with: event)
        }
    }
    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { previewing = false; onPreview(nil) }
        else { super.keyUp(with: event) }
    }
    override func resignFirstResponder() -> Bool {
        if previewing { previewing = false; onPreview(nil) }
        return super.resignFirstResponder()
    }
}
