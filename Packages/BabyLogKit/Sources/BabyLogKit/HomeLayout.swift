import Foundation

/// Which home-screen card a baby shows. Order is the user's order.
/// A feed preference only suggests the starting set. It never deletes history,
/// and a kind with existing records stays available.
public enum HomeCard: String, Codable, CaseIterable, Identifiable, Sendable {
    case breast
    case formula
    case wet
    case dirty
    case diaperChange
    case sleep

    public var id: String { rawValue }

    public static let defaultOrder: [HomeCard] = allCases
}

public enum FeedPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case breast
    case formula
    case mixed

    public var id: String { rawValue }

    /// Suggested visible cards for a baby with no history yet.
    public var suggestedCards: [HomeCard] {
        switch self {
        case .breast:
            return [.breast, .wet, .dirty, .diaperChange, .sleep]
        case .formula:
            return [.formula, .wet, .dirty, .diaperChange, .sleep]
        case .mixed:
            return HomeCard.defaultOrder
        }
    }
}

public struct BabyHomeLayout: Codable, Equatable, Sendable {
    public var preference: FeedPreference
    /// Visible cards, in display order. Hidden cards are simply absent.
    public var cards: [HomeCard]

    public init(preference: FeedPreference = .mixed, cards: [HomeCard]? = nil) {
        self.preference = preference
        self.cards = cards ?? preference.suggestedCards
    }

    /// Keeps the user's order, drops duplicates, and appends any card that already has records
    /// so switching breast/formula never hides history.
    public func resolved(recorded: Set<HomeCard>) -> [HomeCard] {
        var seen = Set<HomeCard>()
        var result: [HomeCard] = []
        for card in cards where seen.insert(card).inserted {
            result.append(card)
        }
        for card in HomeCard.defaultOrder where recorded.contains(card) && seen.insert(card).inserted {
            result.append(card)
        }
        return result
    }

    public func moving(_ card: HomeCard, up: Bool) -> BabyHomeLayout {
        guard let index = cards.firstIndex(of: card) else { return self }
        let next = up ? index - 1 : index + 1
        guard cards.indices.contains(next) else { return self }
        var copy = self
        copy.cards.swapAt(index, next)
        return copy
    }

    public func setting(_ card: HomeCard, visible: Bool) -> BabyHomeLayout {
        var copy = self
        if visible {
            if !copy.cards.contains(card) { copy.cards.append(card) }
        } else {
            copy.cards.removeAll { $0 == card }
        }
        return copy
    }
}

public enum HomeLayoutStore {
    public static let storageKey = "homeLayoutJSON"

    public static func load(babyID: UUID, from data: Data?) -> BabyHomeLayout {
        guard let data,
              let map = try? JSONDecoder().decode([String: BabyHomeLayout].self, from: data),
              let layout = map[babyID.uuidString] else {
            return BabyHomeLayout()
        }
        return layout
    }

    public static func save(_ layout: BabyHomeLayout, babyID: UUID, into data: Data?) -> Data {
        var map = (try? JSONDecoder().decode([String: BabyHomeLayout].self, from: data ?? Data())) ?? [:]
        map[babyID.uuidString] = layout
        return (try? JSONEncoder().encode(map)) ?? Data()
    }
}
