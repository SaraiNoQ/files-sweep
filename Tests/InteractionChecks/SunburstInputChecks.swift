import AppKit
import FileSweepCore

@main
struct SunburstInputChecks {
    @MainActor
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".bench-fixture/input-check-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(count: 200).write(to: folder.appendingPathComponent("inner"))
        try Data(count: 100).write(to: root.appendingPathComponent("file"))
        for i in 0..<650 { try Data(count: 1).write(to: root.appendingPathComponent("match-\(i)")) }
        let snapshot = try FileScanner.scan(root: root)
        let sectors = Sunburst.layout(snapshot, rootID: 0)
        let view = SunburstInputView(frame: NSRect(x: 0,y: 0,width: 500,height: 500))
        view.updateTrackingAreas(); view.updateTrackingAreas()
        assert(view.trackingAreas.count == 1, "visible tracking area is retained across layout updates")
        view.configure(key: "one", sectors: sectors, selection: nil, enabled: true)
        var selected: [Int] = [], activated: [Int] = [], hovered: [Int?] = [], previews: [Int?] = []
        var backCount = 0
        view.onSelect = { selected.append($0) }; view.onActivate = { activated.append($0) }
        view.onHover = { hovered.append($0) }; view.onPreview = { previews.append($0) }; view.onBack = { backCount += 1 }
        func mouse(_ type: NSEvent.EventType, point: CGPoint, count: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: count, pressure: 1)!
        }
        func point(_ sector: SunburstSector) -> CGPoint {
            let angle = (sector.start+sector.end)/2 * 2 * Double.pi - Double.pi/2
            let radius = (Sunburst.innerRadius(depth: sector.depth)+Sunburst.outerRadius(depth: sector.depth))/2 * 250
            return CGPoint(x: 250+cos(angle)*radius,y: 250+sin(angle)*radius)
        }
        func key(_ code: UInt16, up: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: up ? .keyUp : .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }
        for sector in sectors {
            view.mouseDown(with: mouse(.leftMouseDown, point: point(sector)))
            assert(selected.last == sector.id)
            view.mouseDown(with: mouse(.leftMouseDown, point: point(sector), count: 2))
            assert(activated.last == sector.id)
            view.mouseMoved(with: mouse(.mouseMoved, point: point(sector)))
            assert(hovered.last! == sector.id)
        }
        view.mouseMoved(with: mouse(.mouseMoved, point: .zero)); assert(hovered.last! == nil)
        let before = selected.count
        view.mouseDown(with: mouse(.leftMouseDown, point: .zero)); assert(selected.count == before)
        view.mouseDown(with: mouse(.leftMouseDown, point: CGPoint(x: 250,y: 250))); assert(backCount == 1)
        let sector = sectors.first { $0.entryID != nil }!
        view.mouseDown(with: mouse(.leftMouseDown, point: point(sector)))
        view.keyDown(with: key(36)); assert(activated.last == sector.id)
        view.keyDown(with: key(49)); assert(previews.last! == sector.id)
        view.keyUp(with: key(49,up: true)); assert(previews.last! == nil)
        view.keyDown(with: key(49)); view.keyDown(with: key(53)); assert(previews.last! == nil)
        view.keyDown(with: key(51)); assert(backCount == 2)
        view.configure(key: "two", sectors: [], selection: nil, enabled: false)
        let activationCount = activated.count
        view.mouseDown(with: mouse(.leftMouseDown, point: point(sector),count: 2))
        view.keyDown(with: key(36)); assert(activated.count == activationCount)
        view.configure(key: "two", sectors: sectors, selection: sector.entryID, enabled: true)
        view.mouseDown(with: mouse(.leftMouseDown, point: point(sector),count: 2))
        assert(activated.count == activationCount, "double-click from old generation must not activate new geometry")
        view.keyDown(with: key(36)); assert(activated.last == sector.id)
        view.keyDown(with: key(124)); assert(selected.last != nil)
        let group = sectors.first { $0.entryID == nil }!
        view.configure(key: "groups", sectors: [group], selection: nil, enabled: true)
        let selectionsBeforeArrow = selected.count
        view.keyDown(with: key(124)); assert(selected.count == selectionsBeforeArrow && hovered.last! == group.id)
        view.configure(key: "groups", sectors: [group], selection: nil, enabled: true)
        view.keyDown(with: key(36)); assert(activated.last == group.id)
        let model = Workspace(); model.snapshot = snapshot; model.query = "match"
        model.search()
        for _ in 0..<100 where model.searching { try await Task.sleep(for: .milliseconds(10)) }
        assert(model.searchResults?.count == 500 && model.matchCount == 650)
        let tail = snapshot.entries.first { $0.name.hasPrefix("match") && !(model.searchResults ?? []).contains($0.id) }!.id
        model.search(scope: [tail])
        for _ in 0..<100 where model.searching { try await Task.sleep(for: .milliseconds(10)) }
        assert(model.searchResults == [tail] && model.matchCount == 1, "scope must be filtered before the 500-result limit")
        model.search(); model.markStale()
        for _ in 0..<100 where model.searching { try await Task.sleep(for: .milliseconds(10)) }
        assert(model.searchResults == [tail] && model.matchCount == 1, "same-snapshot search retries retain group scope")
        model.query = ""; model.search(scope: group.memberIDs)
        assert(model.searchResults == group.memberIDs)
        model.search(scope: nil); assert(model.searchResults == nil)
        model.search(scope: group.memberIDs)
        model.snapshot?.generation = UUID(); model.search()
        assert(model.searchResults == nil, "new snapshot invalidates old group indices")
        model.shutdown()
        print("PASS: native in-memory mouse, hover, double-click, keyboard, preview, loading/generation and scoped-search checks")
    }
}
