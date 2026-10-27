import Foundation
import Darwin

public struct ScanRootIdentity: Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let canonicalPath: String

    public init(root: URL) throws {
        var metadata = stat()
        guard root.isFileURL, lstat(root.path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFDIR else {
            throw ScanError.invalidRoot("扫描目录已移动、不可访问或变成了符号链接。")
        }
        device = UInt64(UInt32(bitPattern: metadata.st_dev))
        inode = metadata.st_ino
        canonicalPath = root.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

public struct IncrementalResult: Sendable {
    public let snapshot: ScanSnapshot
    public let rescannedDirectories: [URL]
}

public enum IncrementalScanner {
    public static func refresh(_ snapshot: ScanSnapshot, dirtyDirectories: [URL],
                               identity: ScanRootIdentity, forceFullScan: Bool = false,
                               cancellation: ScanCancellation = ScanCancellation()) throws -> IncrementalResult {
        let start = ProcessInfo.processInfo.systemUptime
        guard try ScanRootIdentity(root: snapshot.root) == identity else {
            throw ScanError.failed("扫描根目录已被移动或替换，请重新选择目录。")
        }
        if forceFullScan || !snapshot.supportsIncremental || !snapshot.isComplete || snapshot.isHistorical {
            return try fullScan(snapshot.root, identity: identity, cancellation: cancellation)
        }
        var scopes: Set<Int> = []
        for directory in dirtyDirectories {
            var url = directory.standardizedFileURL
            guard url.pathComponents.starts(with: snapshot.root.pathComponents) else { continue }
            var found: Int?
            while url.pathComponents.count >= snapshot.root.pathComponents.count {
                if let id = snapshot.entryID(at: url), snapshot.entries[id].kind == .directory,
                   isUnlinkedDirectory(url, within: snapshot.root, device: identity.device) { found = id; break }
                url.deleteLastPathComponent()
            }
            scopes.insert(found ?? 0)
        }
        guard !scopes.isEmpty else { return IncrementalResult(snapshot: snapshot, rescannedDirectories: []) }
        if scopes.contains(0) || scopes.count > 64 { return try fullScan(snapshot.root, identity: identity, cancellation: cancellation) }
        scopes = scopes.filter { id in
            var parent = snapshot.entries[id].parent
            while let ancestor = parent {
                if scopes.contains(ancestor) { return false }
                parent = snapshot.entries[ancestor].parent
            }
            return true
        }
        var patches: [Int: ScanSnapshot] = [:]
        var scanned: [URL] = []
        for id in scopes.sorted() {
            guard !cancellation.isCancelled else { throw CancellationError() }
            let url = snapshot.url(for: id)
            let before = try ScanRootIdentity(root: url)
            let patch = try FileScanner.scan(root: url, cancellation: cancellation)
            guard !patch.cancelled else { throw CancellationError() }
            guard try ScanRootIdentity(root: url) == before else { throw ScanError.failed("变化目录在扫描中被移动，请重新扫描。") }
            patches[id] = patch; scanned.append(url)
        }
        var entries: [ScanEntry] = []
        var expectedCount = snapshot.entries.count
        for (scope, patch) in patches {
            var oldCount = 0
            var pending = [scope]
            while let id = pending.popLast() {
                oldCount += 1
                pending.append(contentsOf: snapshot.children(of: id))
            }
            expectedCount += patch.entries.count - oldCount
        }
        entries.reserveCapacity(expectedCount)
        var pending: [(Int, Int?)] = [(0, nil)]
        var seenLinks: Set<LinkIdentity> = []
        var linkedIDs: Set<LinkIdentity> = []
        for entry in snapshot.entries where entry.linkCount > 1 { linkedIDs.insert(LinkIdentity(device: entry.device, inode: entry.inode)) }
        for patch in patches.values {
            for entry in patch.entries where entry.linkCount > 1 { linkedIDs.insert(LinkIdentity(device: entry.device, inode: entry.inode)) }
        }

        func append(_ source: ScanEntry, parent: Int?) {
            var entry = source
            entry.id = entries.count; entry.parent = parent; entry.firstChild = nil; entry.nextSibling = nil
            entry.logicalBytes = entry.kind == .directory ? 0 : source.logicalBytes
            entry.allocatedBytes = source.ownAllocatedBytes
            let identity = LinkIdentity(device: entry.device, inode: entry.inode)
            if entry.kind != .directory && linkedIDs.contains(identity), !seenLinks.insert(identity).inserted { entry.allocatedBytes = 0 }
            if let parent { entry.nextSibling = entries[parent].firstChild; entries[parent].firstChild = entry.id }
            entries.append(entry)
        }

        while let (oldID, parent) = pending.popLast() {
            if entries.count % 256 == 0 && cancellation.isCancelled { throw CancellationError() }
            if let patch = patches[oldID] {
                let offset = entries.count
                for entry in patch.entries { append(entry, parent: entry.parent.map { $0 + offset } ?? parent) }
            } else {
                let newID = entries.count
                append(snapshot.entries[oldID], parent: parent)
                for child in snapshot.children(of: oldID).reversed() { pending.append((child, newID)) }
            }
        }
        for id in entries.indices.reversed() {
            if let parent = entries[id].parent {
                let logical = entries[parent].logicalBytes.addingReportingOverflow(entries[id].logicalBytes)
                let allocated = entries[parent].allocatedBytes.addingReportingOverflow(entries[id].allocatedBytes)
                guard !logical.overflow, !allocated.overflow else { throw ScanError.failed("目录大小超出可表示范围。") }
                entries[parent].logicalBytes = logical.partialValue
                entries[parent].allocatedBytes = allocated.partialValue
                entries[parent].incomplete = entries[parent].incomplete || entries[id].incomplete
            }
        }
        guard try ScanRootIdentity(root: snapshot.root) == identity, !cancellation.isCancelled else { throw CancellationError() }
        let issueCount = patches.values.reduce(0) { $0 + $1.issueCount }
        let issues = Array(patches.values.flatMap(\.issues).prefix(100))
        var result = ScanSnapshot(root: snapshot.root, entries: entries, issues: issues,
            issueCount: issueCount, cancelled: false, elapsed: ProcessInfo.processInfo.systemUptime - start)
        result.supportsIncremental = true
        return IncrementalResult(snapshot: result, rescannedDirectories: scanned)
    }

    private static func fullScan(_ root: URL, identity: ScanRootIdentity, cancellation: ScanCancellation) throws -> IncrementalResult {
        let result = try FileScanner.scan(root: root, cancellation: cancellation)
        guard !result.cancelled else { throw CancellationError() }
        guard try ScanRootIdentity(root: root) == identity else { throw ScanError.failed("扫描根目录已被替换。") }
        return IncrementalResult(snapshot: result, rescannedDirectories: [root])
    }

    private static func isUnlinkedDirectory(_ url: URL, within root: URL, device: UInt64) -> Bool {
        var cursor = root
        for component in url.pathComponents.dropFirst(root.pathComponents.count) {
            cursor.appendPathComponent(component)
            var metadata = stat()
            guard lstat(cursor.path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFDIR,
                  UInt64(UInt32(bitPattern: metadata.st_dev)) == device else { return false }
        }
        return true
    }
}

private struct LinkIdentity: Hashable { let device: UInt64; let inode: UInt64 }
