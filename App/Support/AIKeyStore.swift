import Foundation
import Security
import BabyLogKit

/// API keys stay in the Keychain on this device only. They are not synced, logged, or put in the snapshot.
enum AIKeyStore {
    private static let service = "com.harrisliangsu.littlebabylog.ai"

    static func save(_ token: String, provider: AIProviderID) {
        save(token, account: provider.rawValue)
    }

    static func save(_ token: String, account: String) {
        delete(account: account)
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
        if let active = AIConfigurationCatalog.load().active, active.provider == provider {
            return token(account: active.id.uuidString) ?? token(account: provider.rawValue)
        }
        return token(account: provider.rawValue)
    }

    static func token(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(provider: AIProviderID) {
        delete(account: provider.rawValue)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func lastFour(account: String) -> String {
        guard let token = token(account: account), token.count >= 4 else { return "" }
        return String(token.suffix(4))
    }

    static func lastFour(provider: AIProviderID) -> String {
        lastFour(account: AIConfigurationCatalog.load().active?.id.uuidString ?? provider.rawValue)
    }

    /// Copies provider-keyed keys into configuration accounts once. The old item is removed only after the copy reads back.
    static func migrateLegacyConfigurations() {
        let defaults = UserDefaults.standard
        guard defaults.data(forKey: AIConfigurationCatalog.storageKey) == nil else { return }
        var keys: [String: String] = [:]
        for provider in AIProviderID.allCases {
            if let token = token(account: provider.rawValue) { keys[provider.rawValue] = token }
        }
        let result = AIConfigurationMigration.migrate(
            storedProvider: defaults.string(forKey: AIPreferences.providerKey),
            modelJSON: defaults.string(forKey: AIPreferences.modelsKey) ?? "",
            keys: keys
        )
        for move in result.moves {
            save(move.token, account: move.toAccount)
            if token(account: move.toAccount) == move.token {
                delete(account: move.fromAccount)
            }
        }
        result.catalog.save()
    }
}

enum AIPreferences {
    static let enabledKey = "aiAssistEnabled"
    static let providerKey = "aiAssistProvider"
    static let voiceNoticeKey = "aiVoiceNoticeAck"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var provider: AIProviderID {
        if let active = AIConfigurationCatalog.load().active { return active.provider }
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
        if let active = AIConfigurationCatalog.load().active, active.provider == provider {
            return active.model
        }
        return selection().current(for: provider)
    }

    static func setModel(_ rawID: String, for provider: AIProviderID) {
        UserDefaults.standard.set(selection().choosing(rawID, for: provider).json, forKey: modelsKey)
    }
}
