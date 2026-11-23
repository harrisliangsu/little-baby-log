import Foundation

public struct AIProviderConfiguration: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var provider: AIProviderID
    public var model: String

    public init(id: UUID = UUID(), provider: AIProviderID, model: String) {
        self.id = id
        self.provider = provider
        self.model = AIModelCatalog.resolve(model, for: provider)
    }
}

public struct AIConfigurationCatalog: Codable, Equatable, Sendable {
    public static let storageKey = "aiAssistConfigurations"

    public var items: [AIProviderConfiguration]
    public var activeID: UUID?

    public init(items: [AIProviderConfiguration] = [], activeID: UUID? = nil) {
        self.items = items
        self.activeID = activeID
    }

    public var active: AIProviderConfiguration? {
        items.first { $0.id == activeID }
    }

    public func deleting(_ id: UUID) -> AIConfigurationCatalog {
        var copy = self
        copy.items.removeAll { $0.id == id }
        if copy.activeID == id { copy.activeID = nil }
        return copy
    }

    public func activating(_ id: UUID) -> AIConfigurationCatalog {
        guard items.contains(where: { $0.id == id }) else { return self }
        var copy = self
        copy.activeID = id
        return copy
    }

    public static func load(from defaults: UserDefaults = .standard) -> AIConfigurationCatalog {
        guard let data = defaults.data(forKey: storageKey),
              let catalog = try? JSONDecoder().decode(AIConfigurationCatalog.self, from: data) else {
            return AIConfigurationCatalog()
        }
        return catalog
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

public enum AIConfigurationMigration {
    public static let legacyDeepSeek = UUID(uuidString: "11111111-1111-4111-8111-111111111001")!
    public static let legacyKimiAI = UUID(uuidString: "11111111-1111-4111-8111-111111111002")!
    public static let legacyKimiCN = UUID(uuidString: "11111111-1111-4111-8111-111111111003")!

    public struct KeyMove: Equatable, Sendable {
        public var fromAccount: String
        public var toAccount: String
        public var token: String
    }

    public static func legacyID(_ provider: AIProviderID) -> UUID {
        switch provider {
        case .deepseek: return legacyDeepSeek
        case .kimiAI: return legacyKimiAI
        case .kimiCN: return legacyKimiCN
        }
    }

    /// One configuration per provider that already has a key. The previously selected provider stays current.
    /// A key for a provider that was not selected is kept, but not used until the person chooses it.
    public static func migrate(storedProvider: String?, modelJSON: String, keys: [String: String]) -> (catalog: AIConfigurationCatalog, moves: [KeyMove]) {
        let models = AIModelSelection(json: modelJSON)
        var items: [AIProviderConfiguration] = []
        var moves: [KeyMove] = []
        for provider in AIProviderID.allCases {
            let token = keys[provider.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !token.isEmpty else { continue }
            let id = legacyID(provider)
            items.append(AIProviderConfiguration(id: id, provider: provider, model: models.current(for: provider)))
            moves.append(KeyMove(fromAccount: provider.rawValue, toAccount: id.uuidString, token: token))
        }
        let explicit = storedProvider.flatMap(AIProviderID.init(rawValue:))
        let active = items.first { $0.provider == explicit }?.id
            ?? (storedProvider == nil ? items.first { $0.provider == .deepseek }?.id : nil)
        return (AIConfigurationCatalog(items: items, activeID: active), moves)
    }
}
