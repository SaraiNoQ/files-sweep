import Foundation

/// An allowlist payload: arbitrary names and paths never enter the type.
/// This is a preview only. There is intentionally no network client in v0.1.
public struct ExplanationContext: Encodable, Sendable {
    public let schemaVersion = 1
    public let kind: EntryKind
    public let sizeBand: String
    public let nameHint: String
    public let scanComplete: Bool
    public let personalData: String = "unknown"
    public let actionPolicy: String = "read_only_user_decides"
    public let children: [ChildSummary]
    public let childrenTruncated: Bool

    public struct ChildSummary: Encodable, Sendable {
        public let alias: String
        public let kind: EntryKind
        public let nameHint: String
    }

    public init(snapshot: ScanSnapshot, entryID: Int) {
        let entry = snapshot.entries[entryID]
        kind = entry.kind
        switch entry.logicalBytes {
        case ..<1_048_576: sizeBand = "below_1_MiB"
        case ..<104_857_600: sizeBand = "1_to_100_MiB"
        case ..<1_073_741_824: sizeBand = "100_MiB_to_1_GiB"
        case ..<10_737_418_240: sizeBand = "1_to_10_GiB"
        default: sizeBand = "above_10_GiB"
        }
        nameHint = Self.hint(entry.name)
        scanComplete = snapshot.isComplete && !entry.incomplete
        let ids = snapshot.children(of: entryID)
        children = ids.prefix(20).enumerated().map { offset, id in
            ChildSummary(alias: "item-\(offset + 1)", kind: snapshot.entries[id].kind,
                         nameHint: Self.hint(snapshot.entries[id].name))
        }
        childrenTruncated = ids.count > 20
    }

    public func preview() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
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
