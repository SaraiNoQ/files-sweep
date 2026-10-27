import Foundation
import Darwin
import CoreGraphics
import FileSweepCore

@main
struct ScanChecks {
    static func main() async throws {
        let checks = ScanChecks()
        try checks.testTreeAggregationAndSymlinkBoundary()
        try checks.testHardlinksCountAllocationOnceAndMatchDu()
        try checks.testCancelledScanCannotClaimComplete()
        try checks.testMissingRootAndSymlinkRootRejected()
        try checks.testUnreadableDirectoryIsNotEmptySuccess()
        try checks.testRedaction()
        checks.testTreemapAreas()
        checks.testTreemapExtremeRatios()
        checks.testReadableTreemap()
        try checks.testSunburstAnglesAndHierarchy()
        try checks.testSunburstGroupingAndBudget()
        try checks.testSunburstEmptyCancellationAndExtremes()
        try checks.testSunburstHitTestingAndGroupProgress()
        try checks.testDeveloperRecognition()
        try checks.testAmbiguousNamesAndSymlinkMarkers()
        try checks.testDeveloperProtectionPropagation()
        try checks.testPartialScanProtectsCandidates()
        try checks.testAnalysisNeverExpandsSnapshotScope()
        try checks.testDefaultPathsNeedStructureAndUserScope()
        try checks.testAmbiguousToolchainsAndNestedCandidates()
        try checks.testArchiveRoundTripAndHistoricalProtection()
        try checks.testArchiveRejectsMalformedTreesAndFormats()
        try checks.testArchiveAtomicFailureAndSymlinkRefusal()
        try checks.testArchivePreservesPartialStateAndLargeSizes()
        try checks.testIncrementalMatchesFullScanAndLimitsIO()
        try checks.testIncrementalDirectoryRemovalAndSymlinkBoundary()
        try checks.testIncrementalHardlinksAcrossScopes()
        try checks.testIncrementalRecoveryAndRootReplacement()
        try checks.testEventPlanningAndStaleProtection()
        try checks.testIncrementalPermissionFailureAndRepair()
        try await checks.testLiveDirectoryMonitor()
        try await checks.testLiveRootMoveStopsScope()
        print("PASS: 32 filesystem, incremental, live-monitor, protection, archive and layout checks")
    }
    func fixture(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    func testTreeAggregationAndSymlinkBoundary() throws {
        try fixture { root in
            let nested = root.appendingPathComponent("project/cache")
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data(repeating: 65, count: 8192).write(to: nested.appendingPathComponent("file.bin"))
            try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("loop").path, withDestinationPath: root.path)
            let scan = try FileScanner.scan(root: root)
            assert(scan.isComplete)
            assert(scan.entries.count == 5)
            assert(scan.entries.filter { $0.kind == .symbolicLink }.count == 1)
            let file = scan.entries.first { $0.name == "file.bin" }!
            assert(scan.url(for: file.id).path == nested.appendingPathComponent("file.bin").path)
            assert(scan.entries[1].parent == 0)
            assert(scan.entries[0].logicalBytes >= 8192)
        }
    }

    func testHardlinksCountAllocationOnceAndMatchDu() throws {
        try fixture { root in
            let file = root.appendingPathComponent("first")
            try Data(repeating: 42, count: 16384).write(to: file)
            try FileManager.default.linkItem(at: file, to: root.appendingPathComponent("second"))
            let scan = try FileScanner.scan(root: root)
            assert(scan.entries[0].logicalBytes == 32768)
            let files = scan.entries.filter { $0.kind == .file }
            assert(files.filter { $0.allocatedBytes == 0 }.count == 1)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
            process.arguments = ["-sk", root.path]
            let pipe = Pipe(); process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let kilobytes = UInt64(String(decoding: data, as: UTF8.self).split(separator: "\t")[0])!
            assert(scan.entries[0].allocatedBytes == kilobytes * 1024)
        }
    }

    func testCancelledScanCannotClaimComplete() throws {
        try fixture { root in
            let token = ScanCancellation(); token.cancel()
            let scan = try FileScanner.scan(root: root, cancellation: token)
            assert(scan.cancelled)
            assert(!scan.isComplete)
        }
    }

    func testMissingRootAndSymlinkRootRejected() throws {
        assert((try? FileScanner.scan(root: URL(fileURLWithPath: "/filesweep-missing-\(UUID())"))) == nil)
        try fixture { root in
            let link = root.appendingPathComponent("alias")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
            assert((try? FileScanner.scan(root: link)) == nil)
        }
    }

    func testUnreadableDirectoryIsNotEmptySuccess() throws {
        try fixture { root in
            let blocked = root.appendingPathComponent("blocked")
            try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
            chmod(blocked.path, 0)
            defer { chmod(blocked.path, 0o700) }
            let scan = try FileScanner.scan(root: root)
            assert(!scan.isComplete)
            assert(scan.issueCount > 0)
            assert(scan.entries[0].incomplete)
        }
    }

    func testRedaction() throws {
        try fixture { root in
            let privateName = "private-customer-identity-123.txt"
            try Data("SECRET FILE CONTENT".utf8).write(to: root.appendingPathComponent(privateName))
            let scan = try FileScanner.scan(root: root)
            let payload = try ExplanationContext(snapshot: scan, entryID: 0).preview()
            assert(!payload.contains(root.path))
            assert(!payload.contains(privateName))
            assert(!payload.contains("SECRET FILE CONTENT"))
            assert(payload.contains("item-1"))
            assert(payload.contains("unknown"))
        }
    }

    func testTreemapAreas() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)
        let tiles = Treemap.layout([(0, 60), (1, 30), (2, 10), (3, 0)], in: bounds)
        assert(tiles.count == 3)
        for tile in tiles {
            assert(bounds.contains(tile.rect))
            let expected = [0: 0.6, 1: 0.3, 2: 0.1][tile.id]!
            assert(abs(tile.rect.width * tile.rect.height / 400000 - expected) < 0.000001)
        }
        for a in tiles.indices {
            for b in tiles.indices where a < b {
                let overlap = tiles[a].rect.intersection(tiles[b].rect)
                assert(overlap.isNull || overlap.width * overlap.height < 0.000001)
            }
        }
        assert(Treemap.layout([], in: bounds).isEmpty)
    }

    func testTreemapExtremeRatios() {
        let tiles = Treemap.layout([(0, UInt64.max - 2), (1, 1), (2, 1)],
                                   in: CGRect(x: 0, y: 0, width: 800, height: 500))
        assert(tiles.count == 3)
        for tile in tiles {
            assert([tile.rect.minX, tile.rect.minY, tile.rect.width, tile.rect.height].allSatisfy(\.isFinite))
            assert(tile.rect.width >= 0 && tile.rect.height >= 0)
        }
    }

    func testReadableTreemap() {
        assert(Treemap.includes(kind: .directory, bytes: 0))
        assert(!Treemap.includes(kind: .file, bytes: 10 * 1024 * 1024))
        assert(Treemap.includes(kind: .file, bytes: 10 * 1024 * 1024 + 1))
        assert(!Treemap.includes(kind: .symbolicLink, bytes: .max))
        assert(!Treemap.includes(kind: .other, bytes: .max))
        let values: [(id: Int, bytes: UInt64)] = [(3, 0), (2, 2), (1, 8), (0, UInt64.max - 10)]
        let bounds = CGRect(x: 10, y: 20, width: 900, height: 240)
        let regions = Treemap.readableLayout(values[...], in: bounds)
        assert(regions.count == values.count)
        assert(regions.last!.rect.height > regions.first!.rect.height)
        assert(regions.map(\.logicalBytes) == values.map(\.bytes))
        assert(Set(regions.flatMap { $0.itemRange }) == Set(values.indices))
        for region in regions {
            assert(region.rect.width >= 144 - 0.000001 && region.rect.height >= 76 - 0.000001)
            assert(region.rect.minX >= bounds.minX && region.rect.maxX <= bounds.maxX + 0.000001)
            assert(region.rect.minY >= bounds.minY && region.rect.maxY <= bounds.maxY + 0.000001)
        }
        for a in regions.indices {
            for b in regions.indices where a < b {
                let overlap = regions[a].rect.intersection(regions[b].rect)
                assert(overlap.isNull || overlap.width * overlap.height < 0.000001)
            }
        }
        assert(abs(regions.reduce(0) { $0 + $1.rect.width * $1.rect.height } - bounds.width * bounds.height) < 0.000001)
        let many = (0..<10000).map { (id: $0, bytes: UInt64($0)) }
        let packed = Treemap.readableLayout(many[...], in: bounds)
        assert(packed.count <= 18)
        assert(packed.first!.itemRange.count > 1)
        assert(Set(packed.flatMap { $0.itemRange }) == Set(many.indices))
        assert(packed.reduce(0) { $0 + $1.itemRange.count } == many.count)
        let group = packed.first!.itemRange
        let children = Treemap.readableLayout(many[group], in: bounds, insideGroup: true)
        assert(children.count > 1 && children.count <= 18)
        assert(children.allSatisfy { $0.itemRange.count < group.count })
        assert(Set(children.flatMap { $0.itemRange }) == Set(group))
        assert(children.reduce(0) { $0 + $1.logicalBytes } == many[group].reduce(0) { $0 + $1.bytes })
        let moderate = many[0..<33]
        let moderateGroups = Treemap.readableLayout(moderate, in: bounds, insideGroup: true)
        assert(moderateGroups.first!.itemRange.count > 1)
        assert(moderateGroups.dropFirst().allSatisfy { $0.itemRange.count == 1 })
        let compactGroups = Treemap.readableLayout(moderate, in: CGRect(x: 0, y: 0, width: 900, height: 100), insideGroup: true)
        assert(compactGroups.count <= 6 && compactGroups.allSatisfy { $0.itemRange.count <= 6 })
        let zeros = (0..<50).map { (id: $0, bytes: UInt64(0)) }
        let zeroRegions = Treemap.readableLayout(zeros[...], in: bounds)
        assert(!zeroRegions.isEmpty && zeroRegions.allSatisfy { $0.logicalBytes == 0 })
        assert(Set(zeroRegions.flatMap { $0.itemRange }) == Set(zeros.indices))
        assert(Treemap.readableLayout(values[...], in: .zero).isEmpty)
        assert(Treemap.readableLayout(values[...], in: CGRect(x: 0, y: 0, width: 144, height: 76), insideGroup: true).isEmpty)
        assert(Treemap.readableLayout(values[...], in: CGRect(x: 0, y: 0, width: 80, height: 50)).isEmpty)
    }
}
