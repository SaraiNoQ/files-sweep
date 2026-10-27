import Foundation
import FileSweepCore

extension ScanChecks {
    func testSunburstAnglesAndHierarchy() throws {
        try fixture { root in
            let a = root.appendingPathComponent("A")
            let nested = a.appendingPathComponent("nested")
            let b = root.appendingPathComponent("B")
            for url in [a, nested, b] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
            try Data(count: 40).write(to: a.appendingPathComponent("first"))
            try Data(count: 20).write(to: nested.appendingPathComponent("second"))
            try Data(count: 30).write(to: b.appendingPathComponent("third"))
            try Data(count: 10).write(to: root.appendingPathComponent("fourth"))
            let scan = try FileScanner.scan(root: root)
            let sectors = Sunburst.layout(scan, rootID: 0)
            let first = sectors.filter { $0.depth == 0 }
            assert(first.count == 3)
            assert(abs(first[0].end - 0.6) < 1e-12)
            assert(abs(first[1].end - 0.9) < 1e-12)
            assert(first.last!.end == 1)
            assert(first.map(\.logicalBytes) == [60, 30, 10])
            for sector in sectors {
                assert(sector.start.isFinite && sector.end.isFinite && sector.start >= 0 && sector.end <= 1)
                assert(sector.end > sector.start && sector.depth < Sunburst.maximumDepth)
                if sector.depth > 0 {
                    let parent = sectors.first { $0.entryID == sector.parentID }!
                    assert(sector.start >= parent.start && sector.end <= parent.end)
                    assert(sector.colorIndex == parent.colorIndex)
                    assert(abs((sector.end - sector.start) - Double(sector.logicalBytes) / 100) < 1e-12)
                }
            }
            let sub = Sunburst.layout(scan, rootID: first[0].entryID!)
            assert(sub.filter { $0.depth == 0 }.map(\.logicalBytes) == [40, 20])
            assert(sub.first!.start == 0 && sub.filter { $0.depth == 0 }.last!.end == 1)
        }
    }

    func testSunburstGroupingAndBudget() throws {
        try fixture { root in
            for i in 0..<10 {
                let directory = root.appendingPathComponent("directory-\(i)")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for j in 0..<6 {
                    let nested = directory.appendingPathComponent("nested-\(j)")
                    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
                    for (k, bytes) in [99, 99, 1].enumerated() {
                        try Data(count: bytes).write(to: nested.appendingPathComponent("item-\(k)"))
                    }
                }
            }
            let scan = try FileScanner.scan(root: root)
            let sectors = Sunburst.layout(scan, rootID: 0)
            assert(sectors.count == Sunburst.maximumSectors)
            assert(Set(sectors.map(\.id)).count == sectors.count)
            assert(sectors.contains { $0.entryID == nil && $0.itemCount > 1 })
            for (parentID, children) in Dictionary(grouping: sectors, by: \.parentID) {
                assert(children.reduce(UInt64(0)) { $0 + $1.logicalBytes } == scan.entries[parentID].logicalBytes)
                let ordered = children.sorted { $0.start < $1.start }
                for pair in zip(ordered, ordered.dropFirst()) { assert(abs(pair.0.end - pair.1.start) < 1e-12) }
            }
            assert(sectors.filter { $0.depth == 0 }.reduce(UInt64(0)) { $0 + $1.logicalBytes } == 11_940)
        }
    }

    func testSunburstEmptyCancellationAndExtremes() throws {
        try fixture { root in
            let empty = try FileScanner.scan(root: root)
            assert(Sunburst.layout(empty, rootID: 0).isEmpty)
            assert(Sunburst.layout(empty, rootID: -1).isEmpty)
            try Data(count: 3).write(to: root.appendingPathComponent("large"))
            try Data(count: 1).write(to: root.appendingPathComponent("tiny"))
            try Data().write(to: root.appendingPathComponent("zero"))
            var scan = try FileScanner.scan(root: root)
            let large = scan.entries.first { $0.name == "large" }!.id
            let tiny = scan.entries.first { $0.name == "tiny" }!.id
            let zero = scan.entries.first { $0.name == "zero" }!.id
            assert(Sunburst.layout(scan, rootID: large).isEmpty)
            let token = ScanCancellation(); token.cancel()
            assert(Sunburst.layout(scan, rootID: 0, cancellation: token).isEmpty)
            scan.entries[large].logicalBytes = UInt64.max - 1
            scan.entries[tiny].logicalBytes = 1
            scan.entries[0].logicalBytes = .max
            let sectors = Sunburst.layout(scan, rootID: 0)
            assert(sectors.count == 2)
            assert(!sectors.contains { $0.entryID == zero })
            assert(sectors.reduce(UInt64(0)) { $0 + $1.logicalBytes } == UInt64.max)
            assert(sectors.allSatisfy { $0.start.isFinite && $0.end.isFinite && $0.start <= $0.end && $0.end <= 1 })
        }
    }
}

extension ScanChecks {
    func testSunburstHitTestingAndGroupProgress() throws {
        try fixture { root in
            let folder = root.appendingPathComponent("folder")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for i in 0..<300 { try Data(count: 1).write(to: folder.appendingPathComponent("small-\(i)")) }
            try Data(count: 300).write(to: root.appendingPathComponent("large"))
            let snapshot = try FileScanner.scan(root: root)
            let sectors = Sunburst.layout(snapshot, rootID: 0)
            for size in [CGSize(width: 500, height: 500), CGSize(width: 700, height: 350)] {
                let radius = min(size.width, size.height) / 2
                assert(Sunburst.hitTest(CGPoint(x: size.width/2, y: size.height/2), size: size, sectors: sectors) == .center)
                assert(Sunburst.hitTest(.zero, size: size, sectors: sectors) == nil)
                for sector in sectors where sector.end > sector.start {
                    let angle = (sector.start + sector.end) / 2 * 2 * Double.pi - Double.pi/2
                    let r = (Sunburst.innerRadius(depth: sector.depth) + Sunburst.outerRadius(depth: sector.depth))/2 * radius
                    let point = CGPoint(x: size.width/2 + cos(angle)*r, y: size.height/2 + sin(angle)*r)
                    assert(Sunburst.hitTest(point, size: size, sectors: sectors) == .sector(sector.id))
                }
                let gap = CGPoint(x: size.width/2, y: size.height/2 - radius * 0.305)
                assert(Sunburst.hitTest(gap, size: size, sectors: sectors) == nil)
            }
            assert(Sunburst.hitTest(.zero, size: .zero, sectors: sectors) == nil)
            assert(Sunburst.hitTest(CGPoint(x: Double.nan, y: 0), size: CGSize(width: 500,height: 500), sectors: sectors) == nil)
            let aggregate = sectors.first { $0.entryID == nil }!
            assert(aggregate.memberIDs.count == 300)
            var pending = [aggregate.memberIDs]
            var seen: Set<Int> = []
            var steps = 0
            while let members = pending.popLast() {
                steps += 1; assert(steps < 100)
                let scoped = Sunburst.layout(snapshot, rootID: aggregate.parentID, scope: members)
                let top = scoped.filter { $0.depth == 0 }
                assert(top.reduce(UInt64(0)) { $0 + $1.logicalBytes } == UInt64(members.count))
                for sector in top {
                    if let id = sector.entryID { assert(seen.insert(id).inserted) }
                    else {
                        assert(!sector.memberIDs.isEmpty && sector.memberIDs.count < members.count)
                        pending.append(sector.memberIDs)
                    }
                }
            }
            assert(seen == Set(aggregate.memberIDs))
            let first = aggregate.memberIDs[0]
            let filtered = Sunburst.layout(snapshot, rootID: aggregate.parentID, scope: [first, first, -1, 0, Int.max])
            assert(filtered.count == 1 && filtered[0].entryID == first && filtered[0].logicalBytes == 1)
        }
    }
}
