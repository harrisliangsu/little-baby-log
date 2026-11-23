import Foundation

/// One food on a solids record. Spoons are optional so an older name-only record is not treated as a spoon count.
public struct SolidsFood: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var spoons: Double?

    public init(id: UUID = UUID(), name: String, spoons: Double? = nil) {
        self.id = id
        self.name = name
        self.spoons = spoons
    }
}

/// Several foods share one water amount. The water is not repeated per food and is not a mixing recipe.
public struct SolidsDetail: Codable, Equatable, Sendable {
    public var items: [SolidsFood]
    public var waterML: Double?

    public init(items: [SolidsFood] = [], waterML: Double? = nil) {
        self.items = items
        self.waterML = waterML
    }

    public static let empty = SolidsDetail()

    public var namesSummary: String {
        items.map(\.name).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "、")
    }

    /// A saved JSON wins. Otherwise the old food name stays a single item with no spoon count and no water.
    public static func reading(foodName: String?, json: String?) -> SolidsDetail {
        if let json, let data = json.data(using: .utf8), let detail = try? JSONDecoder().decode(SolidsDetail.self, from: data) {
            return detail
        }
        let name = foodName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return .empty }
        return SolidsDetail(items: [SolidsFood(name: name)], waterML: nil)
    }

    public var json: String? {
        let kept = items.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !kept.isEmpty || waterML != nil else { return nil }
        let detail = SolidsDetail(items: kept, waterML: waterML)
        guard let data = try? JSONEncoder().encode(detail) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// New ids, same names, spoons, and water. Time and record id are not copied.
    public func reused() -> SolidsDetail {
        SolidsDetail(
            items: items.map { SolidsFood(name: $0.name, spoons: $0.spoons) },
            waterML: waterML
        )
    }
}
