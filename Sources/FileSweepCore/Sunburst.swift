import Foundation
import CoreGraphics

public struct SunburstSector: Identifiable, Sendable {
    public let id: Int
    public let entryID: Int?
    public let parentID: Int
    public let depth: Int
    public let start: Double
    public let end: Double
    public let logicalBytes: UInt64
    public let itemCount: Int
    public let colorIndex: Int
    public let memberIDs: [Int]
}

public enum SunburstHit: Equatable, Sendable {
    case center
    case sector(Int)
}

public enum Sunburst {
    public static let maximumSectors = 180
    public static let maximumDepth = 3

    /// Fractions of one clockwise turn; small siblings share one truthful aggregate.
    public static func layout(_ snapshot: ScanSnapshot, rootID: Int, scope: [Int]? = nil,
                              cancellation: ScanCancellation = ScanCancellation()) -> [SunburstSector] {
        guard snapshot.entries.indices.contains(rootID), snapshot.entries[rootID].kind == .directory,
              snapshot.entries[rootID].logicalBytes > 0, !cancellation.isCancelled else { return [] }
        var sectors: [SunburstSector] = []
        var queue: [(parent: Int, depth: Int, start: Double, end: Double, color: Int?)] = [(rootID, 0, 0, 1, nil)]
        var cursor = 0
        while cursor < queue.count && sectors.count < maximumSectors {
            if cancellation.isCancelled { return [] }
            let node = queue[cursor]; cursor += 1
            var children: [Int] = []
            let candidates = node.depth == 0 ? (scope ?? snapshot.children(of: node.parent)) : snapshot.children(of: node.parent)
            var seen: Set<Int> = []
            for (offset, id) in candidates.enumerated() {
                if offset % 256 == 0 && cancellation.isCancelled { return [] }
                guard snapshot.entries.indices.contains(id), snapshot.entries[id].parent == node.parent else { continue }
                if scope != nil && node.depth == 0 && !seen.insert(id).inserted { continue }
                if snapshot.entries[id].logicalBytes > 0 { children.append(id) }
            }
            guard !children.isEmpty else { continue }
            children.sort {
                let a = snapshot.entries[$0], b = snapshot.entries[$1]
                return a.logicalBytes == b.logicalBytes ? a.id < b.id : a.logicalBytes > b.logicalBytes
            }
            if cancellation.isCancelled { return [] }
            let sum = children.reduce(0.0) { $0 + Double(snapshot.entries[$1].logicalBytes) }
            guard sum > 0, sum.isFinite else { continue }
            let span = node.end - node.start
            let capacity = min(24, maximumSectors - sectors.count)
            var individualCount = children.prefix { span * Double(snapshot.entries[$0].logicalBytes) / sum >= 0.008 }.count
            individualCount = min(individualCount, capacity)
            if individualCount < children.count { individualCount = min(individualCount, capacity - 1) }
            func group(_ members: ArraySlice<Int>) -> (id: Int?, bytes: UInt64, members: [Int]) {
                let bytes = members.reduce(UInt64(0)) { value, id in
                    let next = value.addingReportingOverflow(snapshot.entries[id].logicalBytes)
                    return next.overflow ? .max : next.partialValue
                }
                return (members.count == 1 ? members.first : nil, bytes, Array(members))
            }
            var groups: [(id: Int?, bytes: UInt64, members: [Int])] = []
            if node.depth == 0 && scope != nil && children.count > capacity * 2 {
                // Balanced subgroups make repeated entry progress even for millions of tiny siblings.
                let chunk = (children.count + capacity - 1) / capacity
                for offset in stride(from: 0, to: children.count, by: chunk) {
                    groups.append(group(children[offset..<min(children.count, offset + chunk)]))
                }
            } else {
                if node.depth == 0 && scope != nil && children.count <= capacity { individualCount = children.count }
                groups = children.prefix(individualCount).map { ($0, snapshot.entries[$0].logicalBytes, [$0]) }
                if individualCount < children.count { groups.append(group(children.dropFirst(individualCount))) }
            }
            var start = node.start
            for (index, group) in groups.enumerated() {
                let end = index == groups.count - 1 ? node.end : min(node.end, start + span * Double(group.bytes) / sum)
                let color = node.color ?? index
                let sector = SunburstSector(id: sectors.count, entryID: group.id, parentID: node.parent,
                    depth: node.depth, start: start, end: end, logicalBytes: group.bytes,
                    itemCount: group.members.count, colorIndex: color, memberIDs: group.id == nil ? group.members : [])
                sectors.append(sector)
                if let id = group.id, snapshot.entries[id].kind == .directory,
                   node.depth + 1 < maximumDepth, end - start >= 0.016 {
                    queue.append((id, node.depth + 1, start, end, color))
                }
                start = end
            }
        }
        return cancellation.isCancelled ? [] : sectors
    }

    public static func innerRadius(depth: Int) -> Double { 0.32 + Double(depth) * 0.22 }
    public static func outerRadius(depth: Int) -> Double { 0.54 + Double(depth) * 0.22 }

    /// Uses flipped view coordinates and exactly the same radii as the drawing.
    public static func hitTest(_ point: CGPoint, size: CGSize, sectors: [SunburstSector]) -> SunburstHit? {
        let radius = min(size.width, size.height) / 2
        guard radius.isFinite, radius > 0, point.x.isFinite, point.y.isFinite else { return nil }
        let x = Double((point.x - size.width / 2) / radius)
        let y = Double((point.y - size.height / 2) / radius)
        let distance = hypot(x, y)
        if distance <= 0.29 { return .center }
        var turn = (atan2(y, x) + .pi / 2) / (2 * .pi)
        if turn < 0 { turn += 1 }
        guard let sector = sectors.first(where: {
            distance >= innerRadius(depth: $0.depth) && distance < outerRadius(depth: $0.depth)
                && turn >= $0.start && turn < $0.end
        }) else { return nil }
        return .sector(sector.id)
    }
}
