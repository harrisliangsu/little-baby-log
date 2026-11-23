import Foundation

/// Which saved fields a new record may copy. Time, ids, notes, and measurements start fresh.
public enum RecordDefaults {
    public static func newDraft(
        kind: EventKind,
        bottle: BottleContent? = nil,
        diaper: DiaperKind? = nil,
        events: [LogEvent],
        now: Date,
        formulaPin: Double? = nil
    ) -> EventDraft {
        var draft = EventDraft(kind: kind, now: now)
        draft.notes = ""
        switch kind {
        case .bottle:
            let content = bottle ?? .formula
            draft.bottleContent = content
            draft.startDate = now
            draft.endDate = nil
            draft.amountML = amount(content: content, events: events, pin: formulaPin) ?? 0
        case .solids:
            draft.startDate = now
            draft.endDate = nil
            if let last = latest(kind: .solids, events: events) {
                draft.solids = SolidsDetail.reading(foodName: last.foodName, json: last.solidsDetail).reused()
                draft.foodName = draft.solids.namesSummary
            }
        case .medicine:
            draft.startDate = now
            draft.endDate = nil
            draft.medicineName = latest(kind: .medicine, events: events)?.medicineName ?? ""
            draft.dose = ""
        case .diaper:
            draft.startDate = now
            draft.endDate = nil
            draft.diaperKind = diaper ?? .wet
        case .sleep:
            draft.startDate = now.addingTimeInterval(-3600)
            draft.endDate = now
        case .breastfeed:
            draft.startDate = now
            draft.endDate = now
            draft.leftSeconds = 0
            draft.rightSeconds = 0
            draft.lastSide = nil
        case .pump:
            draft.startDate = now
            draft.leftML = 0
            draft.rightML = 0
            draft.pumpDuration = 0
        case .growth:
            draft.startDate = now
            draft.weightKg = 0
            draft.lengthCm = 0
            draft.headCm = 0
        }
        return draft
    }

    private static func latest(kind: EventKind, events: [LogEvent]) -> LogEvent? {
        events.filter { $0.kind == kind }.max { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    private static func amount(content: BottleContent, events: [LogEvent], pin: Double?) -> Double? {
        let last = events
            .filter { $0.kind == .bottle && ($0.bottleContent ?? .formula) == content && $0.amountML > 0 }
            .max { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }?
            .amountML
        if content == .formula {
            return FormulaPreparedTable.prefill(last: last, pinned: pin)
        }
        return last
    }
}
