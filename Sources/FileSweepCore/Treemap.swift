import Foundation
import CoreGraphics

public struct MapTile: Sendable {
    public let id: Int
    public let rect: CGRect
}

public struct MapRegion: Sendable, Identifiable {
    public var id: Int { itemRange.lowerBound }
    public let itemRange: Range<Int>
    public let logicalBytes: UInt64
    public let rect: CGRect
}

public enum Treemap {
    public static let minimumTileSize = CGSize(width: 144, height: 76)
    public static let minimumFileBytes: UInt64 = 10 * 1024 * 1024

    public static func includes(kind: EntryKind, bytes: UInt64) -> Bool {
        kind == .directory || (kind == .file && bytes > minimumFileBytes)
    }

    /// Values are sorted ascending. Ranges retain their indices for local group navigation.
    public static func readableLayout(_ values: ArraySlice<(id: Int, bytes: UInt64)>, in rect: CGRect,
                                      insideGroup: Bool = false) -> [MapRegion] {
        guard !values.isEmpty, rect.width.isFinite, rect.height.isFinite,
              rect.width >= minimumTileSize.width, rect.height >= minimumTileSize.height else { return [] }
        let columns = min(180, Int(min(180, floor(rect.width / minimumTileSize.width))))
        let rows = min(180, Int(min(180, floor(rect.height / minimumTileSize.height))))
        let total = values.reduce(0.0) { $0 + Double($1.bytes) }
        let dominant = rows > 1 && values.count > 1 && Double(values.last!.bytes) > total / 2
        let capacity = min(180, dominant ? (rows - 1) * columns + 1 : rows * columns)
        guard capacity > 1 || values.count == 1 else { return [] }
        var ranges: [Range<Int>] = []
        if values.count <= capacity {
            ranges = values.indices.map { $0..<($0 + 1) }
        } else if insideGroup && values.count > capacity * 2 {
            // Balanced groups avoid linear, one-item-at-a-time navigation through a huge tail.
            let chunk = values.count / capacity + (values.count % capacity == 0 ? 0 : 1)
            var start = values.startIndex
            while start < values.endIndex {
                let end = start + min(chunk, values.endIndex - start)
                ranges.append(start..<end)
                start = end
            }
        } else {
            let end = values.endIndex - capacity + 1
            ranges = [values.startIndex..<end] + (end..<values.endIndex).map { $0..<($0 + 1) }
        }
        let sizes = ranges.map { range in
            values[range].reduce(0 as UInt64) { sum, value in
                let next = sum.addingReportingOverflow(value.bytes)
                return next.overflow ? .max : next.partialValue
            }
        }
        var rowIndices: [Range<Int>] = []
        let bodyCount = dominant && ranges.count > 1 ? ranges.count - 1 : ranges.count
        var start = 0
        while start < bodyCount {
            let end = min(start + columns, bodyCount)
            rowIndices.append(start..<end)
            start = end
        }
        if bodyCount < ranges.count { rowIndices.append(bodyCount..<ranges.count) }
        let heights = fittedLengths(rowIndices.map { row in row.reduce(0.0) { $0 + Double(sizes[$1]) } },
                                    total: rect.height, minimum: minimumTileSize.height)
        var regions: [MapRegion] = []
        var y = rect.minY
        for (rowNumber, row) in rowIndices.enumerated() {
            let height = rowNumber == rowIndices.count - 1 ? rect.maxY - y : heights[rowNumber]
            let widths = fittedLengths(row.map { Double(sizes[$0]) }, total: rect.width, minimum: minimumTileSize.width)
            var x = rect.minX
            for (column, index) in row.enumerated() {
                let width = index == row.last! ? rect.maxX - x : widths[column]
                regions.append(MapRegion(itemRange: ranges[index], logicalBytes: sizes[index],
                                         rect: CGRect(x: x, y: y, width: width, height: height)))
                x += width
            }
            y += height
        }
        return regions
    }

    private static func fittedLengths(_ weights: [Double], total: CGFloat, minimum: CGFloat) -> [CGFloat] {
        var lengths = Array(repeating: CGFloat.zero, count: weights.count)
        var pending = Array(weights.indices)
        var remaining = total
        while !pending.isEmpty {
            let sum = pending.reduce(0.0) { $0 + weights[$1] }
            if sum == 0 {
                for index in pending { lengths[index] = remaining / CGFloat(pending.count) }
                break
            }
            let small = pending.filter { remaining * CGFloat(weights[$0] / sum) < minimum }
            if small.isEmpty {
                for index in pending { lengths[index] = remaining * CGFloat(weights[index] / sum) }
                break
            }
            for index in small { lengths[index] = minimum; remaining -= minimum }
            let fixed = Set(small)
            pending.removeAll { fixed.contains($0) }
        }
        return lengths
    }

    /// Balanced binary partition: stable, area-proportional, bounded depth.
    public static func layout(_ values: [(id: Int, bytes: UInt64)], in rect: CGRect) -> [MapTile] {
        let values = values.filter { $0.bytes > 0 }.sorted {
            $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes
        }
        guard !values.isEmpty, rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else { return [] }
        var tiles: [MapTile] = []
        func divide(_ slice: ArraySlice<(id: Int, bytes: UInt64)>, _ box: CGRect, _ total: Double) {
            guard slice.count > 1 else {
                if let value = slice.first { tiles.append(MapTile(id: value.id, rect: box)) }
                return
            }
            var sum = 0.0
            var split = slice.startIndex
            while split < slice.endIndex - 1 {
                let next = sum + Double(slice[split].bytes)
                if split > slice.startIndex && abs(total / 2 - sum) < abs(total / 2 - next) { break }
                sum = next
                split += 1
            }
            let fraction = sum / total
            let horizontal = box.width >= box.height
            let first = CGRect(x: box.minX, y: box.minY,
                               width: horizontal ? box.width * fraction : box.width,
                               height: horizontal ? box.height : box.height * fraction)
            let second = CGRect(x: horizontal ? first.maxX : box.minX,
                                y: horizontal ? box.minY : first.maxY,
                                width: horizontal ? box.width - first.width : box.width,
                                height: horizontal ? box.height : box.height - first.height)
            divide(slice[..<split], first, sum)
            // Subtraction loses small weights beside a very large sparse file.
            divide(slice[split...], second, slice[split...].reduce(0) { $0 + Double($1.bytes) })
        }
        divide(values[...], rect, values.reduce(0) { $0 + Double($1.bytes) })
        return tiles
    }
}
