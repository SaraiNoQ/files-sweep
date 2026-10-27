import Foundation
import Darwin
import CSQLite

public enum ScanArchiveError: Error, LocalizedError {
    case invalid, limit, database(String), write
    public var errorDescription: String? {
        switch self {
        case .invalid: return "这不是有效的 FileSweep 扫描记录，或记录结构已损坏。"
        case .limit: return "扫描记录超过当前导入限制（200 万条目、512 MiB）。"
        case .database(let detail): return "扫描记录数据库错误：\(detail)"
        case .write: return "无法保存扫描记录，请检查目标位置的权限与可用空间。"
        }
    }
}

/// SQLite is the macOS system library. Archives contain metadata, never file contents.
public enum ScanArchive {
    private static let maxEntries = 2_000_000
    private static let maxFileBytes: Int64 = 512 * 1024 * 1024

    public static func save(_ snapshot: ScanSnapshot, to url: URL) throws {
        guard url.isFileURL, !snapshot.entries.isEmpty else { throw ScanArchiveError.invalid }
        guard snapshot.entries.count <= maxEntries else { throw ScanArchiveError.limit }
        var targetStat = stat()
        if lstat(url.path, &targetStat) == 0 && targetStat.st_mode & S_IFMT != S_IFREG { throw ScanArchiveError.write }
        let template = url.deletingLastPathComponent().appendingPathComponent(".filesweep-XXXXXX").path
        var pattern = Array(template.utf8CString)
        let descriptor = mkstemp(&pattern)
        guard descriptor >= 0 else { throw ScanArchiveError.write }
        Darwin.close(descriptor)
        let temporary = pattern.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        defer { unlink(temporary); unlink(temporary + "-journal") }
        let db = try ArchiveDatabase(temporary, readOnly: false)
        try db.execute("PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; PRAGMA user_version=1; BEGIN IMMEDIATE; CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL); CREATE TABLE entries(id INTEGER PRIMARY KEY, parent INTEGER, name TEXT NOT NULL, kind TEXT NOT NULL, logical TEXT NOT NULL, allocated TEXT NOT NULL, incomplete INTEGER NOT NULL, modified REAL NOT NULL); CREATE TABLE issues(id INTEGER PRIMARY KEY, path TEXT NOT NULL, message TEXT NOT NULL);")
        let metadata = [
            "format": "FileSweepScan", "root": snapshot.root.path,
            "captured": String(snapshot.capturedAt.timeIntervalSince1970),
            "cancelled": snapshot.cancelled ? "1" : "0", "issueCount": String(snapshot.issueCount),
            "elapsed": String(snapshot.elapsed)
        ]
        try db.statement("INSERT INTO metadata VALUES(?,?)") { statement in
            for (key, value) in metadata {
                try db.bind(key, to: statement, at: 1); try db.bind(value, to: statement, at: 2)
                try db.insert(statement)
            }
        }
        try db.statement("INSERT INTO entries VALUES(?,?,?,?,?,?,?,?)") { statement in
            for entry in snapshot.entries {
                sqlite3_bind_int64(statement, 1, Int64(entry.id))
                if let parent = entry.parent { sqlite3_bind_int64(statement, 2, Int64(parent)) }
                else { sqlite3_bind_null(statement, 2) }
                try db.bind(entry.name, to: statement, at: 3)
                try db.bind(entry.kind.rawValue, to: statement, at: 4)
                try db.bind(String(entry.logicalBytes), to: statement, at: 5)
                try db.bind(String(entry.allocatedBytes), to: statement, at: 6)
                sqlite3_bind_int(statement, 7, entry.incomplete ? 1 : 0)
                sqlite3_bind_double(statement, 8, entry.modified.timeIntervalSince1970)
                try db.insert(statement)
            }
        }
        try db.statement("INSERT INTO issues VALUES(?,?,?)") { statement in
            for (index, issue) in snapshot.issues.enumerated() {
                sqlite3_bind_int64(statement, 1, Int64(index))
                try db.bind(issue.path, to: statement, at: 2)
                try db.bind(issue.message, to: statement, at: 3)
                try db.insert(statement)
            }
        }
        try db.execute("COMMIT")
        db.close()
        var savedStat = stat()
        guard lstat(temporary, &savedStat) == 0, savedStat.st_size <= maxFileBytes else { throw ScanArchiveError.limit }
        guard rename(temporary, url.path) == 0 else { throw ScanArchiveError.write }
    }

    public static func load(from url: URL) throws -> ScanSnapshot {
        var metadataStat = stat()
        guard url.isFileURL, lstat(url.path, &metadataStat) == 0, metadataStat.st_mode & S_IFMT == S_IFREG else { throw ScanArchiveError.invalid }
        guard metadataStat.st_size <= maxFileBytes else { throw ScanArchiveError.limit }
        let db = try ArchiveDatabase(url.path, readOnly: true)
        try db.execute("PRAGMA trusted_schema=OFF")
        var version = 0
        try db.statement("PRAGMA user_version") { statement in
            guard try db.next(statement) else { throw ScanArchiveError.invalid }
            version = Int(sqlite3_column_int(statement, 0))
        }
        guard version == 1 else { throw ScanArchiveError.invalid }
        var tables: Set<String> = []
        try db.statement("SELECT name, type, sql FROM sqlite_master WHERE name IN ('metadata','entries','issues')") { statement in
            while try db.next(statement) {
                let name = try db.text(statement, 0)
                guard try db.text(statement, 1) == "table", try db.text(statement, 2).lowercased().hasPrefix("create table") else { throw ScanArchiveError.invalid }
                tables.insert(name)
            }
        }
        guard tables == ["metadata", "entries", "issues"] else { throw ScanArchiveError.invalid }
        var metadata: [String: String] = [:]
        try db.statement("SELECT key, value FROM metadata LIMIT 7") { statement in
            while try db.next(statement) {
                let key = try db.text(statement, 0)
                guard metadata.updateValue(try db.text(statement, 1), forKey: key) == nil else { throw ScanArchiveError.invalid }
            }
        }
        guard metadata.count == 6, metadata["format"] == "FileSweepScan",
              let root = metadata["root"], root.hasPrefix("/"), !root.contains("\0"),
              URL(fileURLWithPath: root).standardizedFileURL.path == root,
              let captured = Double(metadata["captured"] ?? ""), captured.isFinite, captured >= 0, captured <= 253402300799,
              let elapsed = Double(metadata["elapsed"] ?? ""), elapsed.isFinite, elapsed >= 0,
              let issueCount = Int(metadata["issueCount"] ?? ""), issueCount >= 0,
              let cancelled = metadata["cancelled"], ["0", "1"].contains(cancelled) else { throw ScanArchiveError.invalid }
        var entries: [ScanEntry] = []
        try db.statement("SELECT id, parent, name, kind, logical, allocated, incomplete, modified FROM entries ORDER BY id LIMIT 2000001") { statement in
            while try db.next(statement) {
                guard entries.count < maxEntries else { throw ScanArchiveError.limit }
                let id = Int(sqlite3_column_int64(statement, 0))
                let parent = sqlite3_column_type(statement, 1) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 1))
                let name = try db.text(statement, 2)
                let incomplete = sqlite3_column_int(statement, 6)
                let modified = sqlite3_column_double(statement, 7)
                guard sqlite3_column_type(statement, 0) == SQLITE_INTEGER,
                      sqlite3_column_type(statement, 1) == SQLITE_NULL || sqlite3_column_type(statement, 1) == SQLITE_INTEGER,
                      sqlite3_column_type(statement, 6) == SQLITE_INTEGER,
                      [SQLITE_INTEGER, SQLITE_FLOAT].contains(sqlite3_column_type(statement, 7)),
                      id == entries.count,
                      let kind = EntryKind(rawValue: try db.text(statement, 3)),
                      let logical = UInt64(try db.text(statement, 4)),
                      let allocated = UInt64(try db.text(statement, 5)),
                      [0, 1].contains(incomplete), modified.isFinite, abs(modified) <= 253402300799,
                      !name.isEmpty, !name.contains("\0"), name.utf8.count <= 4096 else { throw ScanArchiveError.invalid }
                if id == 0 {
                    guard parent == nil, kind == .directory else { throw ScanArchiveError.invalid }
                } else {
                    guard let parent, parent >= 0, parent < id, entries[parent].kind == .directory,
                          ![".", ".."].contains(name), !name.contains("/") else { throw ScanArchiveError.invalid }
                }
                entries.append(ScanEntry(id: id, parent: parent, name: name, kind: kind,
                    logicalBytes: logical, allocatedBytes: allocated, incomplete: incomplete == 1,
                    modified: Date(timeIntervalSince1970: modified)))
                if let parent {
                    entries[id].nextSibling = entries[parent].firstChild
                    entries[parent].firstChild = id
                }
            }
        }
        guard !entries.isEmpty else { throw ScanArchiveError.invalid }
        // Validate aggregate sizes before the UI sums them or draws a treemap.
        for entry in entries where entry.kind == .directory {
            var logical: UInt64 = 0
            var allocated: UInt64 = 0
            var cursor = entry.firstChild
            while let id = cursor {
                let l = logical.addingReportingOverflow(entries[id].logicalBytes)
                let a = allocated.addingReportingOverflow(entries[id].allocatedBytes)
                guard !l.overflow, !a.overflow else { throw ScanArchiveError.invalid }
                logical = l.partialValue; allocated = a.partialValue
                cursor = entries[id].nextSibling
            }
            guard entry.logicalBytes == logical, entry.allocatedBytes >= allocated else { throw ScanArchiveError.invalid }
        }
        var issues: [ScanIssue] = []
        try db.statement("SELECT path, message FROM issues ORDER BY id LIMIT 101") { statement in
            while try db.next(statement) {
                guard issues.count < 100 else { throw ScanArchiveError.invalid }
                issues.append(ScanIssue(path: try db.text(statement, 0), message: try db.text(statement, 1)))
            }
        }
        guard issueCount >= issues.count else { throw ScanArchiveError.invalid }
        return ScanSnapshot(root: URL(fileURLWithPath: root), entries: entries, issues: issues,
                            issueCount: issueCount, cancelled: cancelled == "1", elapsed: elapsed,
                            capturedAt: Date(timeIntervalSince1970: captured), isHistorical: true)
    }
}

private final class ArchiveDatabase {
    private var handle: OpaquePointer?
    init(_ path: String, readOnly: Bool) throws {
        let flags = (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE) | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            if let handle { sqlite3_close(handle) }; handle = nil
            throw ScanArchiveError.database(message)
        }
        sqlite3_busy_timeout(handle, 1000)
        sqlite3_limit(handle, SQLITE_LIMIT_LENGTH, 65536)
        sqlite3_limit(handle, SQLITE_LIMIT_COLUMN, 32)
    }
    deinit { close() }
    func close() { if let handle { sqlite3_close(handle) }; handle = nil }
    private var failure: ScanArchiveError { .database(String(cString: sqlite3_errmsg(handle))) }
    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure }
    }
    func statement(_ sql: String, body: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure }
        defer { sqlite3_finalize(statement) }
        try body(statement)
    }
    func bind(_ value: String, to statement: OpaquePointer, at index: Int32) throws {
        guard !value.contains("\0"), sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK else { throw failure }
    }
    func insert(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure }
        sqlite3_reset(statement); sqlite3_clear_bindings(statement)
    }
    func next(_ statement: OpaquePointer) throws -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw failure
        }
    }
    func text(_ statement: OpaquePointer, _ column: Int32) throws -> String {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
              let pointer = sqlite3_column_text(statement, column) else { throw ScanArchiveError.invalid }
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count <= 32768, let value = String(bytes: UnsafeBufferPointer(start: pointer, count: count), encoding: .utf8), !value.contains("\0") else { throw ScanArchiveError.invalid }
        return value
    }
}
