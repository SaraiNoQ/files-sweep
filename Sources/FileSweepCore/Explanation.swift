import Foundation

/// An allowlist payload: arbitrary names and paths never enter the type.
public struct ExplanationContext: Encodable, Sendable {
    public let schemaVersion = 2
    public let kind: EntryKind
    public let sizeBand: String
    public let nameHint: String
    public let roleHint: String
    public let scanComplete: Bool
    public let historical: Bool
    public let stale: Bool
    public let localRuleID: String?
    public let localEcosystem: String?
    public let localArtifactKind: String?
    public let localProtection: String
    public let usageState = "unknown"
    public let versionControlState = "unknown"
    public let rebuildability = "unknown"
    public let personalData: String = "unknown"
    public let actionPolicy: String = "read_only_user_decides"
    public let evidenceScope = "captured_scan_snapshot_not_live_state"
    public let children: [ChildSummary]
    public let childrenTruncated: Bool

    public struct ChildSummary: Encodable, Sendable {
        public let alias: String
        public let kind: EntryKind
        public let nameHint: String
        public let roleHint: String
    }

    public init(snapshot: ScanSnapshot, entryID: Int, finding: DeveloperFinding? = nil) {
        let entry = snapshot.entries[entryID]
        historical = snapshot.isHistorical
        stale = snapshot.isStale
        let finding = finding.flatMap { $0.entryID == entryID && Self.ruleIDs.contains($0.ruleID) ? $0 : nil }
        localRuleID = finding?.ruleID
        localEcosystem = finding?.ecosystem.rawValue
        localArtifactKind = finding?.kind.rawValue
        localProtection = snapshot.isHistorical || snapshot.isStale || !snapshot.isComplete || entry.incomplete || finding?.isProtected == true
            ? "protected" : finding == nil ? "unknown" : "requires_manual_verification"
        kind = entry.kind
        switch entry.logicalBytes {
        case ..<1_048_576: sizeBand = "below_1_MiB"
        case ..<104_857_600: sizeBand = "1_to_100_MiB"
        case ..<1_073_741_824: sizeBand = "100_MiB_to_1_GiB"
        case ..<10_737_418_240: sizeBand = "1_to_10_GiB"
        default: sizeBand = "above_10_GiB"
        }
        nameHint = Self.hint(entry.name)
        roleHint = Self.role(entry.name, kind: entry.kind)
        scanComplete = snapshot.isComplete && !entry.incomplete
        let ids = snapshot.children(of: entryID)
        children = ids.prefix(20).enumerated().map { offset, id in
            ChildSummary(alias: "item-\(offset + 1)", kind: snapshot.entries[id].kind,
                         nameHint: Self.hint(snapshot.entries[id].name),
                         roleHint: Self.role(snapshot.entries[id].name, kind: snapshot.entries[id].kind))
        }
        childrenTruncated = ids.count > 20
    }

    public func preview() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    private static let ruleIDs: Set<String> = [
        "python.bytecode", "python.environment", "python.pytest-cache", "python.mypy-cache", "python.ruff-cache",
        "node.dependencies", "node.next", "node.output-name", "rust.target", "java.maven-target", "java.gradle-build",
        "java.project-cache", "go.build-cache", "go.module-cache", "python.pip-cache", "python.uv-cache",
        "node.npm-cache", "rust.registry-cache", "rust.registry-source", "java.local-repository", "java.user-cache", "node.pnpm-store"
    ]

    private static func role(_ name: String, kind: EntryKind) -> String {
        let name = name.lowercased()
        if kind == .directory && name.hasSuffix(".app") { return "application_bundle" }
        guard kind == .file else { return "unknown" }
        switch (name as NSString).pathExtension {
        case "dmg", "iso": return "disk_image"
        case "zip", "tar", "gz", "7z": return "archive"
        case "pkg": return "installer"
        case "log": return "log_file"
        case "swift", "rs", "py", "js", "ts", "go", "java", "c", "cpp": return "source_code"
        case "pdf", "doc", "docx", "xlsx", "pptx": return "document"
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "mp4", "mov", "mp3", "wav", "m4a": return "media"
        case "sqlite", "sqlite3", "db": return "database"
        default: return "unknown"
        }
    }

    private static func hint(_ name: String) -> String {
        // A name is only a hint, never proof of ownership or disposability.
        switch name {
        case "node_modules": return "node_dependency_directory_name"
        case "target": return "possible_build_directory_name"
        case "__pycache__": return "python_bytecode_directory_name"
        case ".git": return "git_metadata_directory_name"
        case ".venv": return "possible_python_environment_name"
        default: return "unknown"
        }
    }
}
