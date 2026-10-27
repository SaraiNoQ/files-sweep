import Foundation
import Darwin

#if !arch(arm64)
#error("FileSweep supports Apple Silicon only.")
#endif

public enum EntryKind: String, Sendable, Codable {
    case directory, file, symbolicLink, other
}

public struct ScanEntry: Identifiable, Sendable {
    public var id: Int
    public var parent: Int?
    public let name: String
    public let kind: EntryKind
    public var logicalBytes: UInt64
    public var allocatedBytes: UInt64
    public var incomplete: Bool
    public let modified: Date
    public var firstChild: Int? = nil
    public var nextSibling: Int? = nil
    public var ownAllocatedBytes: UInt64 = 0
    public var device: UInt64 = 0
    public var inode: UInt64 = 0
    public var linkCount: UInt32 = 1
}

public struct ScanIssue: Sendable {
    public let path: String
    public let message: String
}

public struct ScanSnapshot: Sendable {
    public let root: URL
    public var entries: [ScanEntry]
    public let issues: [ScanIssue]
    public let issueCount: Int
    public let cancelled: Bool
    public let elapsed: Double
    public var capturedAt = Date()
    public var isHistorical = false
    public var isStale = false
    public var generation = UUID()
    public var supportsIncremental = false

    public var isComplete: Bool { !cancelled && issueCount == 0 }

    public func url(for id: Int) -> URL {
        guard entries.indices.contains(id) else { return root }
        var components: [String] = []
        var cursor = id
        while let parent = entries[cursor].parent {
            components.append(entries[cursor].name)
            cursor = parent
        }
        return components.reversed().reduce(root) { $0.appendingPathComponent($1) }
    }

    public func children(of id: Int) -> [Int] {
        guard entries.indices.contains(id) else { return [] }
        var result: [Int] = []
        var cursor = entries[id].firstChild
        while let child = cursor {
            result.append(child)
            cursor = entries[child].nextSibling
        }
        return result
    }

    public func entryID(at url: URL) -> Int? {
        let rootParts = root.standardizedFileURL.pathComponents
        let parts = url.standardizedFileURL.pathComponents
        guard parts.starts(with: rootParts), !entries.isEmpty else { return nil }
        var id = 0
        for name in parts.dropFirst(rootParts.count) {
            guard let child = children(of: id).first(where: { entries[$0].name == name }) else { return nil }
            id = child
        }
        return id
    }
}

public struct ScanProgress: Sendable {
    public let entryCount: Int
    public let elapsed: Double
}

/// Shared between the UI and the blocking filesystem worker.
public final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    public init() {}
    public func cancel() { lock.withLock { stopped = true } }
    public var isCancelled: Bool { lock.withLock { stopped } }
}

public enum ScanError: Error, LocalizedError {
    case invalidRoot(String)
    case failed(String)
    public var errorDescription: String? {
        switch self {
        case .invalidRoot(let reason), .failed(let reason): return reason
        }
    }
}

private struct FileIdentity: Hashable {
    let device: dev_t
    let inode: ino_t
}

public enum FileScanner {
    /// POSIX fts is supplied by macOS. PHYSICAL avoids following symlinks;
    /// XDEV prevents implicitly entering another mounted volume.
    public static func scan(
        root: URL,
        cancellation: ScanCancellation = ScanCancellation(),
        progress: @Sendable (ScanProgress) -> Void = { _ in }
    ) throws -> ScanSnapshot {
        let start = ProcessInfo.processInfo.systemUptime
        let root = root.standardizedFileURL
        var rootStat = stat()
        guard root.isFileURL, lstat(root.path, &rootStat) == 0,
              rootStat.st_mode & S_IFMT == S_IFDIR else {
            throw ScanError.invalidRoot("请选择可访问的真实文件夹；不接受符号链接作为扫描根目录。")
        }
        guard let rootPath = strdup(root.path) else { throw ScanError.failed("无法分配扫描内存。") }
        defer { free(rootPath) }
        var paths: [UnsafeMutablePointer<CChar>?] = [rootPath, nil]
        let handle = paths.withUnsafeMutableBufferPointer {
            fts_open($0.baseAddress!, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil)
        }
        guard let handle else { throw ScanError.failed(String(cString: strerror(errno))) }
        defer { fts_close(handle) }

        var entries: [ScanEntry] = []
        var ancestors: [Int] = []
        var links: Set<FileIdentity> = []
        var issues: [ScanIssue] = []
        var issueCount = 0
        var lastProgress = start

        func record(_ path: String, _ message: String) {
            issueCount += 1
            // Bound diagnostic storage without hiding the total failure count.
            if issues.count < 100 { issues.append(ScanIssue(path: path, message: message)) }
            if let parent = ancestors.last { entries[parent].incomplete = true }
        }

        while !cancellation.isCancelled {
            errno = 0
            guard let pointer = fts_read(handle) else {
                if errno != 0 { record(root.path, String(cString: strerror(errno))) }
                break
            }
            let item = pointer.pointee
            let info = Int32(item.fts_info)
            let depth = Int(item.fts_level)
            if info == FTS_DP { continue }
            if ancestors.count > depth { ancestors.removeLast(ancestors.count - depth) }
            if info == FTS_DNR {
                record(String(cString: item.fts_path), "无权读取或目录不可访问。")
            }
            if info == FTS_ERR || info == FTS_NS || info == FTS_DC {
                record(String(cString: item.fts_path), "无法读取元数据或目录发生循环。")
                continue
            }
            guard let metadata = item.fts_statp?.pointee else {
                record(String(cString: item.fts_path), "缺失文件元数据。")
                continue
            }
            let mode = metadata.st_mode & S_IFMT
            let kind: EntryKind = mode == S_IFDIR ? .directory : mode == S_IFREG ? .file : mode == S_IFLNK ? .symbolicLink : .other
            let crossesVolume = metadata.st_dev != rootStat.st_dev
            var allocated = UInt64(max(0, metadata.st_blocks)) * 512
            // Attribute a hard-linked file's allocation once within this scan.
            if kind != .directory && metadata.st_nlink > 1 {
                if !links.insert(FileIdentity(device: metadata.st_dev, inode: metadata.st_ino)).inserted { allocated = 0 }
            }
            let name = depth == 0 ? root.lastPathComponent : String(cString: strrchr(item.fts_path, 47).map { $0 + 1 } ?? item.fts_path)
            let id = entries.count
            entries.append(ScanEntry(
                id: id, parent: ancestors.last, name: name, kind: kind,
                logicalBytes: kind == .directory ? 0 : UInt64(max(0, metadata.st_size)),
                allocatedBytes: crossesVolume ? 0 : allocated, incomplete: crossesVolume || info == FTS_DNR,
                modified: Date(timeIntervalSince1970: Double(metadata.st_mtimespec.tv_sec))
            ))
            entries[id].ownAllocatedBytes = crossesVolume ? 0 : UInt64(max(0, metadata.st_blocks)) * 512
            entries[id].device = UInt64(UInt32(bitPattern: metadata.st_dev))
            entries[id].inode = metadata.st_ino
            entries[id].linkCount = UInt32(metadata.st_nlink)
            if let parent = entries[id].parent {
                entries[id].nextSibling = entries[parent].firstChild
                entries[parent].firstChild = id
            }
            if kind == .directory { ancestors.append(id) }
            if crossesVolume { record(String(cString: item.fts_path), "已跳过其他卷。请单独选择该卷扫描。") }
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastProgress >= 0.1 {
                progress(ScanProgress(entryCount: entries.count, elapsed: now - start))
                lastProgress = now
            }
        }
        if cancellation.isCancelled, !entries.isEmpty { entries[0].incomplete = true }
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
        progress(ScanProgress(entryCount: entries.count, elapsed: ProcessInfo.processInfo.systemUptime - start))
        var result = ScanSnapshot(root: root, entries: entries, issues: issues, issueCount: issueCount,
                                  cancelled: cancellation.isCancelled, elapsed: ProcessInfo.processInfo.systemUptime - start)
        result.supportsIncremental = true
        return result
    }
}
