import Foundation
import Combine
import Security
import FileSweepCore

@MainActor
final class AISettings: ObservableObject {
    static let shared = AISettings()

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: "ai.enabled") }
    }
    @Published private(set) var address: String
    @Published private(set) var model: String
    private let defaults: UserDefaults
    private let keychainService: String

    init(defaults: UserDefaults = .standard, keychainService: String = "dev.filesweep.mac.llm") {
        self.defaults = defaults
        self.keychainService = keychainService
        enabled = defaults.bool(forKey: "ai.enabled")
        address = defaults.string(forKey: "ai.address") ?? ""
        model = defaults.string(forKey: "ai.model") ?? ""
    }

    func apiKey() throws -> String {
        guard !address.isEmpty else { return "" }
        let endpoint = try ExplanationEndpoint(address: address, model: model)
        var query = keyQuery(endpoint.url)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            let local = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(endpoint.url.host?.lowercased() ?? "")
            if enabled && !local { throw AISettingsError.missingKey }
            return ""
        }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw AISettingsError.keychain
        }
        return key
    }

    func save(address: String, model: String, apiKey: String, enabled: Bool) throws {
        let endpoint = try ExplanationEndpoint(address: address, model: model)
        let key = apiKey
        guard key.utf8.count <= 4_096,
              key.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else {
            throw AISettingsError.invalidKey
        }
        let host = endpoint.url.host?.lowercased() ?? ""
        let local = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
        guard !enabled || local || !key.isEmpty else { throw AISettingsError.missingKey }

        let query = keyQuery(endpoint.url)
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AISettingsError.keychain }
        } else {
            let attributes: [CFString: Any] = [kSecValueData: Data(key.utf8)]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                var item = query
                item[kSecValueData] = Data(key.utf8)
                item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AISettingsError.keychain }
            } else if status != errSecSuccess {
                throw AISettingsError.keychain
            }
        }
        self.address = endpoint.url.absoluteString
        self.model = endpoint.model
        defaults.set(self.address, forKey: "ai.address")
        defaults.set(self.model, forKey: "ai.model")
        self.enabled = enabled
    }

    func removeKey() throws {
        if !address.isEmpty {
            let endpoint = try ExplanationEndpoint(address: address, model: model)
            let status = SecItemDelete(keyQuery(endpoint.url) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AISettingsError.keychain }
        }
        enabled = false
    }

    private func keyQuery(_ url: URL) -> [CFString: Any] {
        // Credentials belong to the full destination, never to a model or a generic provider slot.
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.scheme == "https" && components.port == 443 || components.scheme == "http" && components.port == 80 {
            components.port = nil
        }
        return [kSecClass: kSecClassGenericPassword,
                kSecAttrService: keychainService,
                kSecAttrAccount: components.url!.absoluteString,
                kSecAttrSynchronizable: false]
    }
}

private enum AISettingsError: LocalizedError {
    case keychain, missingKey, invalidKey

    var errorDescription: String? {
        switch self {
        case .keychain: return "无法访问钥匙串，密钥未更新。请检查系统的钥匙串访问提示后重试。"
        case .missingKey: return "请填写此服务的 API 密钥。"
        case .invalidKey: return "API 密钥过长或含有无效字符。"
        }
    }
}
