import Foundation
import Security
import BabyLogKit

/// API keys stay in the Keychain on this device only. They are not synced, logged, or put in the snapshot.
enum AIKeyStore {
    private static let service = "com.harrisliangsu.littlebabylog.ai"

    static func save(_ token: String, provider: AIProviderID) {
        let account = provider.rawValue
        delete(provider: provider)
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func token(provider: AIProviderID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(provider: AIProviderID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func lastFour(provider: AIProviderID) -> String {
        guard let token = token(provider: provider), token.count >= 4 else { return "" }
        return String(token.suffix(4))
    }
}

enum AIPreferences {
    static let enabledKey = "aiAssistEnabled"
    static let providerKey = "aiAssistProvider"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var provider: AIProviderID {
        let raw = UserDefaults.standard.string(forKey: providerKey) ?? ""
        return AIProviderID(rawValue: raw) ?? .deepseek
    }

    /// One local JSON map, provider id to model id. Not a keychain item.
    static let modelsKey = "aiAssistModels"

    static func selection() -> AIModelSelection {
        AIModelSelection(json: UserDefaults.standard.string(forKey: modelsKey) ?? "")
    }

    /// The model for this provider only. A missing or foreign ID becomes that provider's default.
    static func modelID(for provider: AIProviderID) -> String {
        selection().current(for: provider)
    }

    static func setModel(_ rawID: String, for provider: AIProviderID) {
        UserDefaults.standard.set(selection().choosing(rawID, for: provider).json, forKey: modelsKey)
    }
}
