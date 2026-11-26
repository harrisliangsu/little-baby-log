import Foundation

/// How the person using this phone refers to one baby.
///
/// This is a label only. It is not a CloudKit share role, an invite, or permission to edit.
/// The keys are the local caregiver id and the baby id. A display name is never the key.
public enum CaregiverRelationKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case father
    case mother
    case paternalGrandfather
    case paternalGrandmother
    case maternalGrandfather
    case maternalGrandmother
    case custom

    public var id: String { rawValue }

    public func title(custom: String, chinese: Bool) -> String {
        switch self {
        case .father: return chinese ? "爸爸" : "Dad"
        case .mother: return chinese ? "妈妈" : "Mom"
        case .paternalGrandfather: return chinese ? "爷爷" : "Paternal grandpa"
        case .paternalGrandmother: return chinese ? "奶奶" : "Paternal grandma"
        case .maternalGrandfather: return chinese ? "外公" : "Maternal grandpa"
        case .maternalGrandmother: return chinese ? "外婆" : "Maternal grandma"
        case .custom:
            let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? (chinese ? "自定义" : "Custom") : trimmed
        }
    }
}

public struct CaregiverRelation: Codable, Equatable, Sendable {
    public var managerID: UUID
    public var babyID: UUID
    public var kind: CaregiverRelationKind
    public var customTitle: String

    public init(managerID: UUID, babyID: UUID, kind: CaregiverRelationKind, customTitle: String = "") {
        self.managerID = managerID
        self.babyID = babyID
        self.kind = kind
        self.customTitle = customTitle
    }

    public func title(chinese: Bool) -> String {
        kind.title(custom: customTitle, chinese: chinese)
    }
}

/// A sheet's unsaved choice. Cancel drops this value. Only `committed` is stored.
public struct CaregiverRelationDraft: Equatable, Sendable {
    public var kind: CaregiverRelationKind?
    public var customTitle: String

    public init(kind: CaregiverRelationKind? = nil, customTitle: String = "") {
        self.kind = kind
        self.customTitle = customTitle
    }

    public init(_ stored: CaregiverRelation?) {
        kind = stored?.kind
        customTitle = stored?.customTitle ?? ""
    }

    /// Nil when nothing is selected, or a custom title is still empty.
    public func committed(managerID: UUID, babyID: UUID) -> CaregiverRelation? {
        guard let kind else { return nil }
        if kind == .custom {
            let title = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return CaregiverRelation(managerID: managerID, babyID: babyID, kind: .custom, customTitle: title)
        }
        return CaregiverRelation(managerID: managerID, babyID: babyID, kind: kind, customTitle: "")
    }
}

/// Local to this device. Missing entries stay unset. Saving one baby does not write the others.
public struct CaregiverRelationStore: Sendable {
    public static let relationsKey = "caregiverRelations"
    public static let managerKey = "localCaregiverID"
    public static let didChange = Notification.Name("caregiverRelationDidChange")

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The person using this phone. Created once and reused. Not an iCloud account.
    public func managerID() -> UUID {
        if let raw = defaults.string(forKey: Self.managerKey), let id = UUID(uuidString: raw) {
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: Self.managerKey)
        return id
    }

    public func relation(managerID: UUID, babyID: UUID) -> CaregiverRelation? {
        all().first { $0.managerID == managerID && $0.babyID == babyID }
    }

    public func save(_ relation: CaregiverRelation) {
        var rows = all().filter { !($0.managerID == relation.managerID && $0.babyID == relation.babyID) }
        rows.append(relation)
        write(rows)
    }

    public func clear(managerID: UUID, babyID: UUID) {
        write(all().filter { !($0.managerID == managerID && $0.babyID == babyID) })
    }

    public func all() -> [CaregiverRelation] {
        guard let data = defaults.data(forKey: Self.relationsKey),
              let rows = try? JSONDecoder().decode([CaregiverRelation].self, from: data) else { return [] }
        return rows
    }

    private func write(_ rows: [CaregiverRelation]) {
        let data = try? JSONEncoder().encode(rows)
        defaults.set(data, forKey: Self.relationsKey)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
