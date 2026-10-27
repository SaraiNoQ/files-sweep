import Foundation
import CoreServices

public struct DirectoryChange: Sendable {
    public let path: URL
    public let flags: UInt32
    public init(path: URL, flags: UInt32) { self.path = path; self.flags = flags }
    public var rootChanged: Bool { flags & UInt32(kFSEventStreamEventFlagRootChanged) != 0 }
    public var requiresFullScan: Bool {
        let mask = kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount
        return flags & UInt32(mask) != 0
    }
    public func directory(in root: URL, canonicalRoot: URL) -> URL? {
        let parts = path.standardizedFileURL.pathComponents
        let original = root.standardizedFileURL.pathComponents
        let canonical = canonicalRoot.standardizedFileURL.pathComponents
        let base: [String]
        if parts.starts(with: original) { base = original }
        else if parts.starts(with: canonical) { base = canonical }
        else { return nil }
        let mapped = parts.dropFirst(base.count).reduce(root) { $0.appendingPathComponent($1) }
        if mapped == root || flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0 { return mapped }
        return mapped.deletingLastPathComponent()
    }
}

private final class MonitorCallbackState: @unchecked Sendable {
    let root: URL
    let receive: @Sendable ([DirectoryChange]) -> Void
    init(root: URL, receive: @escaping @Sendable ([DirectoryChange]) -> Void) { self.root = root; self.receive = receive }
}

/// Events are advisory. The owner coalesces changes and performs bounded rescans.
@MainActor
public final class DirectoryMonitor {
    nonisolated(unsafe) private var stream: FSEventStreamRef?

    public init(root: URL, receive: @escaping @Sendable ([DirectoryChange]) -> Void) throws {
        _ = try ScanRootIdentity(root: root)
        let state = MonitorCallbackState(root: root, receive: receive)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(state).toOpaque(), retain: { pointer in
            guard let pointer else { return nil }
            return UnsafeRawPointer(Unmanaged<MonitorCallbackState>.fromOpaque(pointer).retain().toOpaque())
        }, release: { pointer in
            if let pointer { Unmanaged<MonitorCallbackState>.fromOpaque(pointer).release() }
        }, copyDescription: nil)
        let flags = kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer
        let created = withExtendedLifetime(state) {
            FSEventStreamCreate(nil, { _, info, count, rawPaths, flags, _ in
            guard let info else { return }
            let state = Unmanaged<MonitorCallbackState>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(rawPaths, to: NSArray.self)
            var changes: [DirectoryChange] = []
            for index in 0..<min(count, paths.count, 256) {
                guard let path = paths[index] as? String else { continue }
                if flags[index] & UInt32(kFSEventStreamEventFlagHistoryDone) != 0 { continue }
                changes.append(DirectoryChange(path: URL(fileURLWithPath: path), flags: flags[index]))
            }
            if count > 256 { changes.append(DirectoryChange(path: state.root, flags: UInt32(kFSEventStreamEventFlagKernelDropped))) }
            state.receive(changes)
            }, &context, [root.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.35, FSEventStreamCreateFlags(flags))
        }
        guard let stream = created else {
            throw ScanError.failed("无法创建目录变化监听。")
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else { stop(); throw ScanError.failed("无法启动目录变化监听。") }
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
}
