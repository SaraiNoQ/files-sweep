import Foundation
import FileSweepCore

private final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    var values: [String: Any] = [:]
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}

@main
struct AISettingsChecks {
    @MainActor
    static func main() throws {
        let defaults = MemoryDefaults(suiteName: "dev.filesweep.settings-checks")!
        let settings = AISettings(defaults: defaults, keychainService: "dev.filesweep.settings-checks")
        assert(!settings.enabled && settings.address.isEmpty && settings.model.isEmpty)
        let key = try settings.apiKey()
        assert(key.isEmpty)
        settings.enabled = true
        assert(defaults.bool(forKey: "ai.enabled"))
        try settings.removeKey()
        assert(!settings.enabled && !defaults.bool(forKey: "ai.enabled"))

        for key in ["", "key\r\nInjected: value", "with space", "secret密钥123", String(repeating: "x", count: 4_097)] {
            do {
                try settings.save(address: "https://example.com/v1/chat/completions", model: "test", apiKey: key, enabled: true)
                assertionFailure("invalid or missing key must fail before reaching Keychain")
            } catch {
                assert(settings.address.isEmpty && settings.model.isEmpty && !settings.enabled)
                assert(!error.localizedDescription.contains(key) || key.isEmpty)
            }
        }
        assert(Set(defaults.values.keys) == ["ai.enabled"], "only nonsecret settings are persisted")
        print("PASS: AI settings default-off, validation, sanitized errors and nonsecret persistence checks")
    }
}
