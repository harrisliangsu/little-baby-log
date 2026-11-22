import Foundation

/// Frozen at the moment recording starts. Relative phrases are measured from here, not from when a reply arrives.
public struct VoiceAnchor: Equatable, Sendable {
    public var startedAt: Date
    public var timeZone: TimeZone

    public init(startedAt: Date, timeZone: TimeZone) {
        self.startedAt = startedAt
        self.timeZone = timeZone
    }

    public var iso8601: String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: startedAt)
    }

    public func adding(minutes: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(byAdding: .minute, value: minutes, to: startedAt) ?? startedAt.addingTimeInterval(TimeInterval(minutes * 60))
    }
}

public enum VoiceUncertainty: String, Codable, Equatable, Hashable, Sendable {
    case baby, kind, time, amount, detail
}

public enum VoiceNextStep: Equatable, Sendable {
    case preview
    case manual
    case discard

    /// Cancel drops the transcript. A failed or empty recognition goes back to typing. A stopped transcript can be previewed.
    public static func after(stopped: Bool, transcript: String?, failed: Bool) -> VoiceNextStep {
        guard stopped else { return .discard }
        if failed { return .manual }
        let trimmed = transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? .manual : .preview
    }
}

public struct VoiceNameMap: Equatable, Sendable {
    public var currentName: String
    public var tokenToName: [String: String]
    public var mentionedTokens: [String]

    public init(currentName: String, tokenToName: [String: String], mentionedTokens: [String]) {
        self.currentName = currentName
        self.tokenToName = tokenToName
        self.mentionedTokens = mentionedTokens
    }
}

public struct VoiceModelItem: Equatable, Sendable {
    public var kind: String?
    public var baby: String?
    public var minutesAgo: Int?
    public var start: String?
    public var amountML: Double?
    public var durationMinutes: Int?
    public var diaper: String?
    public var bottle: String?
    public var side: String?
    public var food: String?
    public var medicine: String?
    public var uncertain: [String]

    public init(
        kind: String? = nil,
        baby: String? = nil,
        minutesAgo: Int? = nil,
        start: String? = nil,
        amountML: Double? = nil,
        durationMinutes: Int? = nil,
        diaper: String? = nil,
        bottle: String? = nil,
        side: String? = nil,
        food: String? = nil,
        medicine: String? = nil,
        uncertain: [String] = []
    ) {
        self.kind = kind
        self.baby = baby
        self.minutesAgo = minutesAgo
        self.start = start
        self.amountML = amountML
        self.durationMinutes = durationMinutes
        self.diaper = diaper
        self.bottle = bottle
        self.side = side
        self.food = food
        self.medicine = medicine
        self.uncertain = uncertain
    }
}

public struct VoiceItemDraft: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: EventKind?
    public var start: Date?
    public var amountML: Double?
    public var durationMinutes: Int?
    public var diaper: DiaperKind?
    public var bottle: BottleContent?
    public var side: BreastSide?
    public var food: String?
    public var medicine: String?
    public var assignedBabyName: String
    public var conflictsWithCurrentBaby: Bool
    public var uncertain: Set<VoiceUncertainty>
    public var candidateNames: [String]

    public var canWrite: Bool {
        guard let kind, start != nil, uncertain.isEmpty, !conflictsWithCurrentBaby else { return false }
        switch kind {
        case .bottle:
            return (amountML ?? 0) > 0 && bottle != nil
        case .diaper:
            return diaper != nil
        case .sleep:
            let minutes = durationMinutes ?? 0
            return minutes > 0 && minutes <= 24 * 60
        case .breastfeed:
            return (durationMinutes ?? 0) > 0 && side != nil
        case .solids:
            return true
        case .pump, .growth, .medicine:
            return false
        }
    }

    /// Clears uncertainty flags whose values are already present. A baby conflict stays blocked.
    public func confirmed() -> VoiceItemDraft? {
        guard !conflictsWithCurrentBaby, !uncertain.contains(.baby) else { return nil }
        var copy = self
        if kind != nil { copy.uncertain.remove(.kind) }
        if start != nil { copy.uncertain.remove(.time) }
        if (amountML ?? 0) > 0 { copy.uncertain.remove(.amount) }
        if copy.detailIsComplete { copy.uncertain.remove(.detail) }
        guard copy.canWrite else { return nil }
        return copy
    }

    public mutating func confirmBaby(_ name: String) {
        assignedBabyName = name
        conflictsWithCurrentBaby = false
        uncertain.remove(.baby)
    }

    public func eventDraft() -> EventDraft? {
        guard canWrite, let kind, let start else { return nil }
        return makeDraft(kind: kind, start: start)
    }

    /// A form the person can still edit. Nothing is stored until that form is saved.
    public func editableDraft(fallbackStart: Date) -> EventDraft? {
        guard let kind, !conflictsWithCurrentBaby, !uncertain.contains(.baby) else { return nil }
        return makeDraft(kind: kind, start: start ?? fallbackStart)
    }

    private var detailIsComplete: Bool {
        switch kind {
        case .bottle: return bottle != nil && (amountML ?? 0) > 0
        case .diaper: return diaper != nil
        case .sleep: return (durationMinutes ?? 0) > 0
        case .breastfeed: return (durationMinutes ?? 0) > 0 && side != nil
        case .solids: return true
        default: return false
        }
    }

    private func makeDraft(kind: EventKind, start: Date) -> EventDraft {
        var draft = EventDraft(kind: kind, now: start)
        draft.startDate = start
        switch kind {
        case .bottle:
            draft.endDate = nil
            draft.amountML = amountML ?? 0
            draft.bottleContent = bottle ?? .formula
        case .diaper:
            draft.endDate = nil
            draft.diaperKind = diaper ?? .wet
        case .sleep:
            let seconds = TimeInterval((durationMinutes ?? 0) * 60)
            draft.endDate = seconds > 0 ? start.addingTimeInterval(seconds) : nil
        case .breastfeed:
            let seconds = TimeInterval((durationMinutes ?? 0) * 60)
            if side == .right {
                draft.rightSeconds = seconds
                draft.leftSeconds = 0
                draft.lastSide = .right
            } else if side == .left {
                draft.leftSeconds = seconds
                draft.rightSeconds = 0
                draft.lastSide = .left
            }
            draft.endDate = seconds > 0 ? start.addingTimeInterval(seconds) : nil
        case .solids:
            draft.endDate = nil
            draft.foodName = food ?? ""
        case .pump:
            draft.pumpDuration = TimeInterval((durationMinutes ?? 0) * 60)
            draft.leftML = amountML ?? 0
            draft.rightML = 0
        case .medicine:
            draft.endDate = nil
            draft.medicineName = medicine ?? ""
        case .growth:
            draft.endDate = nil
        }
        return draft
    }
}

public enum VoiceDrafts {
    public static func items(from data: Data) throws -> [VoiceModelItem] {
        let object = try AIProposalDecoder.payload(from: data)
        guard let rows = object["items"] as? [[String: Any]] else { throw AIClientError.unreadable }
        return rows.map { row in
            VoiceModelItem(
                kind: row["kind"] as? String,
                baby: row["baby"] as? String,
                minutesAgo: intValue(row["minutesAgo"]),
                start: row["start"] as? String,
                amountML: doubleValue(row["amountML"]),
                durationMinutes: intValue(row["durationMinutes"]),
                diaper: row["diaper"] as? String,
                bottle: row["bottle"] as? String,
                side: row["side"] as? String,
                food: row["food"] as? String,
                medicine: row["medicine"] as? String,
                uncertain: row["uncertain"] as? [String] ?? []
            )
        }
    }

    /// The exact text that would be sent. Baby names are replaced with tokens. Audio is not included.
    public static func outbound(
        transcript: String,
        anchor: VoiceAnchor,
        currentBaby: String,
        otherBabies: [String],
        provider: AIProviderID
    ) -> (preview: AISendPreview, map: VoiceNameMap)? {
        let spoken = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return nil }
        let redacted = redact(transcript: spoken, currentBaby: currentBaby, otherBabies: otherBabies)
        let instruction = """
        锚点 \(anchor.iso8601) \(anchor.timeZone.identifier)。用中文直接回答，不要介绍自己，不要提数据格式。如果是在问好或提问，只写回答，不要下医疗结论，不要编造没有的数据。如果是在记护理，先写一句人话，再附上 <records>{"items":[{"kind":null,"baby":null,"minutesAgo":null,"start":null,"amountML":null,"durationMinutes":null,"diaper":null,"bottle":null,"side":null,"food":null,"medicine":null,"uncertain":[]}]}</records>。kind 只能是 sleep, breastfeed, bottle, solids, diaper, pump, growth, medicine。相对时间用 minutesAgo，从锚点往前数。不确定就放进 uncertain，不要猜。宝宝只用 Current、Baby2 这类代号。
        \(redacted.text)
        """
        let preview = AISendPreview(
            provider: provider,
            task: .recordDraft,
            userText: instruction,
            removedBabyNames: redacted.replaced
        )
        return (preview, redacted.map)
    }

    public static func resolve(items: [VoiceModelItem], anchor: VoiceAnchor, map: VoiceNameMap) -> [VoiceItemDraft] {
        items.map { resolve($0, anchor: anchor, map: map) }
    }

    public static func redact(transcript: String, currentBaby: String, otherBabies: [String]) -> (text: String, map: VoiceNameMap, replaced: Bool) {
        let current = currentBaby.trimmingCharacters(in: .whitespacesAndNewlines)
        var pairs: [(String, String)] = []
        var tokenToName: [String: String] = [:]
        if !current.isEmpty {
            pairs.append((current, "Current"))
            tokenToName["Current"] = current
        }
        var index = 2
        for name in otherBabies {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.caseInsensitiveCompare(current) != .orderedSame else { continue }
            guard !tokenToName.values.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { continue }
            let token = "Baby\(index)"
            index += 1
            pairs.append((trimmed, token))
            tokenToName[token] = trimmed
        }
        pairs.sort { $0.0.count > $1.0.count }
        var text = transcript
        var mentioned: [String] = []
        var replaced = false
        for (name, token) in pairs where text.range(of: name, options: [.caseInsensitive]) != nil {
            text = text.replacingOccurrences(of: name, with: token, options: [.caseInsensitive])
            mentioned.append(token)
            replaced = true
        }
        let map = VoiceNameMap(currentName: current, tokenToName: tokenToName, mentionedTokens: mentioned)
        return (text, map, replaced)
    }

    private static func resolve(_ item: VoiceModelItem, anchor: VoiceAnchor, map: VoiceNameMap) -> VoiceItemDraft {
        var uncertain = Set(item.uncertain.compactMap(VoiceUncertainty.init(rawValue:)))
        let kind = item.kind.flatMap(EventKind.init(rawValue:))
        if kind == nil { uncertain.insert(.kind) }

        let start = resolvedStart(item, anchor: anchor)
        if start == nil { uncertain.insert(.time) }

        let amount = item.amountML
        let duration = item.durationMinutes
        let diaper = item.diaper.flatMap(DiaperKind.init(rawValue:))
        let bottle = item.bottle.flatMap(BottleContent.init(rawValue:))
        let side = item.side.flatMap(BreastSide.init(rawValue:))

        if kind == .bottle, (amount ?? 0) <= 0 { uncertain.insert(.amount) }
        if kind == .bottle, bottle == nil { uncertain.insert(.detail) }
        if kind == .diaper, diaper == nil { uncertain.insert(.detail) }
        if kind == .sleep || kind == .breastfeed, (duration ?? 0) <= 0 { uncertain.insert(.detail) }
        if kind == .breastfeed, side == nil { uncertain.insert(.detail) }
        if kind == .pump || kind == .growth || kind == .medicine { uncertain.insert(.detail) }

        let baby = assignBaby(item.baby, map: map)
        if baby.conflict || baby.uncertain { uncertain.insert(.baby) }

        let names = map.tokenToName.values.sorted { lhs, rhs in
            if lhs == map.currentName { return true }
            if rhs == map.currentName { return false }
            return lhs < rhs
        }

        return VoiceItemDraft(
            id: UUID(),
            kind: kind,
            start: start,
            amountML: amount,
            durationMinutes: duration,
            diaper: diaper,
            bottle: bottle,
            side: side,
            food: item.food,
            medicine: item.medicine,
            assignedBabyName: baby.name,
            conflictsWithCurrentBaby: baby.conflict,
            uncertain: uncertain,
            candidateNames: names
        )
    }

    private static func resolvedStart(_ item: VoiceModelItem, anchor: VoiceAnchor) -> Date? {
        if let minutes = item.minutesAgo {
            return anchor.adding(minutes: -minutes)
        }
        guard let raw = item.start?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty, raw != "null" else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
    }

    private static func assignBaby(_ raw: String?, map: VoiceNameMap) -> (name: String, conflict: Bool, uncertain: Bool) {
        let token = normalizedToken(raw)
        let others = map.mentionedTokens.filter { $0 != "Current" }
        let mentionsCurrent = map.mentionedTokens.contains("Current")
        if let token, token != "Current", let name = map.tokenToName[token] {
            return (name, true, false)
        }
        if others.count == 1, !mentionsCurrent, let name = map.tokenToName[others[0]] {
            return (name, true, false)
        }
        if let token, token != "Current" {
            return (map.currentName, false, true)
        }
        if !others.isEmpty, token == nil {
            return (map.currentName, false, true)
        }
        return (map.currentName, false, false)
    }

    private static func normalizedToken(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "null" { return nil }
        if trimmed.caseInsensitiveCompare("Current") == .orderedSame { return "Current" }
        return trimmed
    }

    private static func intValue(_ value: Any?) -> Int? {
        if value is NSNull { return nil }
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if value is NSNull { return nil }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }
}

public struct SummaryFact: Equatable, Sendable, Identifiable {
    public var id: String
    public var line: String

    public init(id: String, line: String) {
        self.id = id
        self.line = line
    }
}

public enum HistorySummaryText {
    /// Facts already counted on the phone. The model is told not to add percentiles or a health conclusion.
    public static func userText(total: String, facts: [SummaryFact]) -> String {
        let body = facts.map { "\($0.id) \($0.line)" }.joined(separator: "\n")
        return """
        只根据下面这些已经发生的记录写一句摘要。不要写百分位，不要下健康结论，不要补充没有出现的次数或数量。
        合计: \(total)
        \(body)
        返回 JSON {"text":"..."}。
        """
    }
}
