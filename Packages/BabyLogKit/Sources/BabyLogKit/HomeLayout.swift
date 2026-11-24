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
    /// Functions in the record area, in the user's order. Absent cards belong in the other-log area.
    public var cards: [HomeCard]
    /// Cards that show today's extra figures. Missing from older saves, so the default is basic.
    public var detailCards: [HomeCard]

    public init(preference: FeedPreference = .mixed, cards: [HomeCard]? = nil, detailCards: [HomeCard] = []) {
        self.preference = preference
        self.cards = cards ?? preference.suggestedCards
        self.detailCards = detailCards
    }

    private enum CodingKeys: String, CodingKey {
        case preference, cards, detailCards
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preference = try container.decode(FeedPreference.self, forKey: .preference)
        cards = try container.decode([HomeCard].self, forKey: .cards)
        detailCards = try container.decodeIfPresent([HomeCard].self, forKey: .detailCards) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preference, forKey: .preference)
        try container.encode(cards, forKey: .cards)
        try container.encode(detailCards, forKey: .detailCards)
    }

    /// Selected functions, user's order, without duplicates.
    public var recordCards: [HomeCard] {
        var seen = Set<HomeCard>()
        return cards.filter { seen.insert($0).inserted }
    }

    /// Functions that are not in the record area. History is untouched; the card only moves sections.
    public var otherCards: [HomeCard] {
        let selected = Set(recordCards)
        return HomeCard.defaultOrder.filter { !selected.contains($0) }
    }

    public func isDetailed(_ card: HomeCard) -> Bool {
        detailCards.contains(card)
    }

    /// One switch for every record card. History is not touched.
    public var showsDetail: Bool {
        !recordCards.isEmpty && recordCards.allSatisfy { detailCards.contains($0) }
    }

    public func settingDetails(_ enabled: Bool) -> BabyHomeLayout {
        var copy = self
        if enabled {
            for card in recordCards where !copy.detailCards.contains(card) {
                copy.detailCards.append(card)
            }
        } else {
            let visible = Set(recordCards)
            copy.detailCards.removeAll { visible.contains($0) }
        }
        return copy
    }

    /// Moves `card` to the slot currently held by `target`. Other cards keep their relative order.
    public func placing(_ card: HomeCard, before target: HomeCard) -> BabyHomeLayout {
        guard card != target, let from = cards.firstIndex(of: card) else { return self }
        var copy = self
        copy.cards.remove(at: from)
        let index = copy.cards.firstIndex(of: target) ?? copy.cards.endIndex
        copy.cards.insert(card, at: index)
        return copy
    }

    public func settingDetail(_ card: HomeCard, detailed: Bool) -> BabyHomeLayout {
        var copy = self
        if detailed {
            if !copy.detailCards.contains(card) { copy.detailCards.append(card) }
        } else {
            copy.detailCards.removeAll { $0 == card }
        }
        return copy
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
