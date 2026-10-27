import Foundation
import Darwin
import CSQLite
import FileSweepCore

extension ScanChecks {
    func testArchiveRoundTripAndHistoricalProtection() throws {
        try fixture { root in
            let target = root.appendingPathComponent("target/debug")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try Data().write(to: root.appendingPathComponent("Cargo.toml"))
            try Data("fixture".utf8).write(to: target.appendingPathComponent("quote'测试\nfile"))
            let snapshot = try FileScanner.scan(root: root)
            let archive = root.appendingPathComponent("scan.filesweep")
            try ScanArchive.save(snapshot, to: archive)
            let bytes = try Data(contentsOf: archive)
            try FileManager.default.moveItem(at: target, to: root.appendingPathComponent("moved"))
            let loaded = try ScanArchive.load(from: archive)
            assert(loaded.isHistorical && loaded.isComplete)
            assert(loaded.entries.count == snapshot.entries.count)
            assert(loaded.root.path == snapshot.root.path)
            assert(abs(loaded.capturedAt.timeIntervalSince(snapshot.capturedAt)) < 0.001)
            for index in loaded.entries.indices {
                assert(loaded.entries[index].name == snapshot.entries[index].name)
                assert(loaded.entries[index].logicalBytes == snapshot.entries[index].logicalBytes)
                assert(loaded.entries[index].allocatedBytes == snapshot.entries[index].allocatedBytes)
                assert(loaded.url(for: index).path == snapshot.url(for: index).path)
            }
            let findings = DeveloperAnalyzer.analyze(loaded).findings.values
            assert(findings.count == 1)
            assert(findings.allSatisfy(\.isProtected))
            assert(findings.first!.protectionReasons.contains { $0.contains("历史") })
            let readback1 = try Data(contentsOf: archive)
            assert(readback1 == bytes)
            var metadata = stat()
            lstat(archive.path, &metadata)
            assert(metadata.st_mode & 0o777 == 0o600)
        }
    }

    func testArchiveRejectsMalformedTreesAndFormats() throws {
        try fixture { root in
            try Data("data".utf8).write(to: root.appendingPathComponent("file"))
            let snapshot = try FileScanner.scan(root: root)
            let archive = root.appendingPathComponent("scan.filesweep")
            let mutations = [
                "UPDATE entries SET parent=id WHERE id=1",
                "UPDATE entries SET parent=0.5 WHERE id=1",
                "UPDATE entries SET name='..' WHERE id=1",
                "UPDATE entries SET name='escape/path' WHERE id=1",
                "UPDATE entries SET kind='unknown' WHERE id=1",
                "UPDATE entries SET name=printf('%070000d',1) WHERE id=1",
                "UPDATE entries SET logical='18446744073709551615' WHERE id=1",
                "UPDATE metadata SET value='nan' WHERE key='captured'",
                "UPDATE metadata SET value='/tmp/../etc' WHERE key='root'",
                "PRAGMA user_version=999",
                "ALTER TABLE entries RENAME TO old_entries; CREATE VIEW entries AS SELECT * FROM old_entries"
            ]
            for sql in mutations {
                try ScanArchive.save(snapshot, to: archive)
                try mutateArchive(archive, sql)
                assert((try? ScanArchive.load(from: archive)) == nil, sql)
            }
            try Data("not a database".utf8).write(to: archive)
            assert((try? ScanArchive.load(from: archive)) == nil)
        }
    }

    func testArchiveAtomicFailureAndSymlinkRefusal() throws {
        try fixture { root in
            try Data().write(to: root.appendingPathComponent("file"))
            let snapshot = try FileScanner.scan(root: root)
            let archive = root.appendingPathComponent("scan.filesweep")
            try ScanArchive.save(snapshot, to: archive)
            let original = try Data(contentsOf: archive)
            let token = ScanCancellation(); token.cancel()
            let empty = try FileScanner.scan(root: root, cancellation: token)
            do { try ScanArchive.save(empty, to: archive); assertionFailure("Empty archive must fail") } catch {}
            let readback2 = try Data(contentsOf: archive)
            assert(readback2 == original)
            let alias = root.appendingPathComponent("alias.filesweep")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: archive)
            do { try ScanArchive.save(snapshot, to: alias); assertionFailure("Symlink target must fail") } catch {}
            assert((try? ScanArchive.load(from: alias)) == nil)
            let readback3 = try Data(contentsOf: archive)
            assert(readback3 == original)
        }
    }

    func testArchivePreservesPartialStateAndLargeSizes() throws {
        try fixture { root in
            let blocked = root.appendingPathComponent("blocked")
            try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
            chmod(blocked.path, 0)
            defer { chmod(blocked.path, 0o700) }
            let partial = try FileScanner.scan(root: root)
            let archive = root.appendingPathComponent("scan.filesweep")
            try ScanArchive.save(partial, to: archive)
            let loaded = try ScanArchive.load(from: archive)
            assert(!loaded.isComplete && loaded.issueCount == partial.issueCount)
            assert(loaded.issues.count == partial.issues.count)
        }
        try fixture { root in
            try Data().write(to: root.appendingPathComponent("file"))
            var snapshot = try FileScanner.scan(root: root)
            let size = UInt64(Int64.max) + 1
            snapshot.entries[0].logicalBytes = size
            snapshot.entries[1].logicalBytes = size
            let archive = root.appendingPathComponent("scan.filesweep")
            try ScanArchive.save(snapshot, to: archive)
            let loaded = try ScanArchive.load(from: archive)
            assert(loaded.entries[0].logicalBytes == size)
        }
    }

    private func mutateArchive(_ url: URL, _ sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else { throw ScanArchiveError.invalid }
        defer { sqlite3_close(handle) }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw ScanArchiveError.invalid }
    }
}
