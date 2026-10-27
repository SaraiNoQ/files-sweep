import Foundation
import CoreServices
import Darwin
import FileSweepCore

extension ScanChecks {
    func testIncrementalMatchesFullScanAndLimitsIO() throws {
        try fixture { root in
            let a = root.appendingPathComponent("a/cache"), b = root.appendingPathComponent("b")
            try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 4096).write(to: a.appendingPathComponent("old"))
            try Data(repeating: 2, count: 8192).write(to: b.appendingPathComponent("kept"))
            let initial = try FileScanner.scan(root: root)
            let identity = try ScanRootIdentity(root: root)
            try FileManager.default.removeItem(at: a.appendingPathComponent("old"))
            try Data(repeating: 3, count: 16384).write(to: a.appendingPathComponent("new"))
            let update = try IncrementalScanner.refresh(initial, dirtyDirectories: [a, a], identity: identity)
            assert(update.rescannedDirectories.map(\.path) == [a.path])
            let full = try FileScanner.scan(root: root)
            assertSameTree(update.snapshot, full)
            assert(update.snapshot.generation != initial.generation)
            assert(update.snapshot.entryID(at: a.appendingPathComponent("old")) == nil)
            assert(update.snapshot.entryID(at: a.appendingPathComponent("new")) != nil)
            let outside = root.deletingLastPathComponent().appendingPathComponent("outside")
            let ignored = try IncrementalScanner.refresh(update.snapshot, dirtyDirectories: [outside], identity: identity)
            assert(ignored.rescannedDirectories.isEmpty)
        }
    }

    func testIncrementalDirectoryRemovalAndSymlinkBoundary() throws {
        try fixture { root in
            let a = root.appendingPathComponent("a/cache"), b = root.appendingPathComponent("b")
            try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
            try Data("private".utf8).write(to: b.appendingPathComponent("data"))
            let initial = try FileScanner.scan(root: root)
            let identity = try ScanRootIdentity(root: root)
            try FileManager.default.removeItem(at: a)
            try FileManager.default.createSymbolicLink(at: a, withDestinationURL: b)
            let update = try IncrementalScanner.refresh(initial, dirtyDirectories: [a], identity: identity)
            assert(update.rescannedDirectories.map(\.path) == [root.appendingPathComponent("a").path])
            let link = update.snapshot.entryID(at: a)!
            assert(update.snapshot.entries[link].kind == .symbolicLink)
            assert(update.snapshot.entryID(at: a.appendingPathComponent("data")) == nil)
            assertSameTree(update.snapshot, try FileScanner.scan(root: root))
        }
    }

    func testIncrementalHardlinksAcrossScopes() throws {
        try fixture { root in
            let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
            try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
            let source = a.appendingPathComponent("file")
            try Data(repeating: 7, count: 16384).write(to: source)
            let initial = try FileScanner.scan(root: root)
            let identity = try ScanRootIdentity(root: root)
            try FileManager.default.linkItem(at: source, to: b.appendingPathComponent("linked"))
            let update = try IncrementalScanner.refresh(initial, dirtyDirectories: [b], identity: identity)
            let full = try FileScanner.scan(root: root)
            assert(update.snapshot.entries[0].allocatedBytes == full.entries[0].allocatedBytes)
            assert(update.snapshot.entries[0].logicalBytes == full.entries[0].logicalBytes)
        }
    }

    func testIncrementalRecoveryAndRootReplacement() throws {
        try fixture { root in
            let folder = root.appendingPathComponent("watched")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("data".utf8).write(to: folder.appendingPathComponent("file"))
            let initial = try FileScanner.scan(root: folder)
            let identity = try ScanRootIdentity(root: folder)
            let recovery = try IncrementalScanner.refresh(initial, dirtyDirectories: [], identity: identity, forceFullScan: true)
            assert(recovery.rescannedDirectories.map(\.path) == [folder.path])
            let token = ScanCancellation(); token.cancel()
            do {
                _ = try IncrementalScanner.refresh(initial, dirtyDirectories: [folder], identity: identity, cancellation: token)
                assertionFailure("Cancelled updates must not publish partial data")
            } catch {}
            try FileManager.default.moveItem(at: folder, to: root.appendingPathComponent("moved"))
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            do {
                _ = try IncrementalScanner.refresh(initial, dirtyDirectories: [folder], identity: identity)
                assertionFailure("A replaced root must be refused")
            } catch {}
        }
    }

    func testEventPlanningAndStaleProtection() throws {
        let root = URL(fileURLWithPath: "/var/example"), canonical = URL(fileURLWithPath: "/private/var/example")
        let change = DirectoryChange(path: canonical.appendingPathComponent("a/file"), flags: UInt32(kFSEventStreamEventFlagItemModified))
        assert(change.directory(in: root, canonicalRoot: canonical)?.path == root.appendingPathComponent("a").path)
        let outside = DirectoryChange(path: URL(fileURLWithPath: "/var/example-other/file"), flags: 0)
        assert(outside.directory(in: root, canonicalRoot: canonical) == nil)
        assert(DirectoryChange(path: root, flags: UInt32(kFSEventStreamEventFlagKernelDropped)).requiresFullScan)
        assert(DirectoryChange(path: root, flags: UInt32(kFSEventStreamEventFlagRootChanged)).rootChanged)
        try fixture { root in
            let target = root.appendingPathComponent("target/debug")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try Data().write(to: root.appendingPathComponent("Cargo.toml"))
            var snapshot = try FileScanner.scan(root: root)
            snapshot.isStale = true
            assert(DeveloperAnalyzer.analyze(snapshot).findings.values.allSatisfy(\.isProtected))
        }
    }

    func testIncrementalPermissionFailureAndRepair() throws {
        try fixture { root in
            let folder = root.appendingPathComponent("a/blocked")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("owned fixture".utf8).write(to: folder.appendingPathComponent("file"))
            let initial = try FileScanner.scan(root: root)
            let identity = try ScanRootIdentity(root: root)
            chmod(folder.path, 0)
            defer { chmod(folder.path, 0o700) }
            let partial = try IncrementalScanner.refresh(initial, dirtyDirectories: [root.appendingPathComponent("a")], identity: identity)
            assert(!partial.snapshot.isComplete)
            assert(partial.snapshot.entries[0].incomplete)
            chmod(folder.path, 0o700)
            let repaired = try IncrementalScanner.refresh(partial.snapshot, dirtyDirectories: [folder], identity: identity)
            assert(repaired.snapshot.isComplete)
            assert(repaired.rescannedDirectories.map(\.path) == [root.path])
            assertSameTree(repaired.snapshot, try FileScanner.scan(root: root))
        }
    }

    private func assertSameTree(_ incremental: ScanSnapshot, _ full: ScanSnapshot) {
        assert(incremental.entries.count == full.entries.count)
        for entry in incremental.entries {
            let url = incremental.url(for: entry.id)
            guard let id = full.entryID(at: url) else { assertionFailure("Missing path \(url.path)"); continue }
            assert(entry.kind == full.entries[id].kind)
            assert(entry.logicalBytes == full.entries[id].logicalBytes)
            assert(entry.allocatedBytes == full.entries[id].allocatedBytes)
        }
    }
}

private actor EventRecorder {
    var events: [DirectoryChange] = []
    func append(_ changes: [DirectoryChange]) { events.append(contentsOf: changes) }
    var count: Int { events.count }
    var rootChanged: Bool { events.contains(where: \.rootChanged) }
}

extension ScanChecks {
    func testLiveDirectoryMonitor() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = EventRecorder()
        let monitor = try await MainActor.run {
            try DirectoryMonitor(root: root) { events in Task { await recorder.append(events) } }
        }
        try Data("one".utf8).write(to: root.appendingPathComponent("observed"))
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while await recorder.count == 0 && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let received = await recorder.count
        assert(received > 0, "FSEvents did not deliver the generated file change")
        await monitor.stop()
        try await Task.sleep(for: .milliseconds(200))
        let stopped = await recorder.count
        try Data("two".utf8).write(to: root.appendingPathComponent("after-stop"))
        try await Task.sleep(for: .milliseconds(800))
        let finalCount = await recorder.count
        assert(finalCount == stopped, "Stopped monitor received new events")
        for _ in 0..<5 {
            let shortLived = try await MainActor.run {
                try DirectoryMonitor(root: root) { events in Task { await recorder.append(events) } }
            }
            await shortLived.stop()
        }
    }

    func testLiveRootMoveStopsScope() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = parent.appendingPathComponent("watched")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let recorder = EventRecorder()
        let monitor = try await MainActor.run {
            try DirectoryMonitor(root: root) { events in Task { await recorder.append(events) } }
        }
        try FileManager.default.moveItem(at: root, to: parent.appendingPathComponent("moved"))
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while await !recorder.rootChanged && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let changed = await recorder.rootChanged
        await monitor.stop()
        assert(changed, "Root rename must produce a scope invalidation")
    }
}
