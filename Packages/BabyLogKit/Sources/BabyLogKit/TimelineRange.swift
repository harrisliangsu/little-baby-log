import Foundation

/// Date window for a category timeline. All boundaries use the caller's calendar,
/// so a record at 23:30 stays on that local day.
public enum TimelineRange: Equatable, Sendable {
    case today
    case yesterday
    case last7Days
    case all
    case day(Date)

    public func contains(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else { return false }
            return calendar.isDate(date, inSameDayAs: yesterday)
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
            return date >= start && date <= now.addingTimeInterval(60)
        case .day(let day):
            return calendar.isDate(date, inSameDayAs: day)
        }
    }
}

public enum HomeCardMatch {
    public static func card(for event: LogEvent) -> HomeCard? {
        switch event.kind {
        case .breastfeed: return .breast
        case .bottle where event.bottleContent == .formula: return .formula
        case .diaper where event.diaperKind == .wet: return .wet
        case .diaper where event.diaperKind == .dirty: return .dirty
        case .diaper where event.diaperKind == .dry: return .diaperChange
        case .diaper where event.diaperKind == .mixed: return .wet
        case .sleep: return .sleep
        default: return nil
        }
    }

    /// Mixed diapers also appear on the dirty timeline.
    public static func matches(_ event: LogEvent, card: HomeCard) -> Bool {
        switch card {
        case .breast: return event.kind == .breastfeed
        case .formula: return event.kind == .bottle && event.bottleContent == .formula
        case .wet: return event.kind == .diaper && event.diaperKind?.isWet == true
        case .dirty: return event.kind == .diaper && event.diaperKind?.isDirty == true
        case .diaperChange: return event.kind == .diaper && event.diaperKind == .dry
        case .sleep: return event.kind == .sleep
        }
    }

    public static func recordedCards(in events: [LogEvent]) -> Set<HomeCard> {
        var set = Set<HomeCard>()
        for event in events {
            switch event.kind {
            case .breastfeed: set.insert(.breast)
            case .bottle where event.bottleContent == .formula: set.insert(.formula)
            case .diaper where event.diaperKind?.isWet == true: set.insert(.wet)
            case .diaper where event.diaperKind?.isDirty == true: set.insert(.dirty)
            case .diaper where event.diaperKind == .dry: set.insert(.diaperChange)
            case .sleep: set.insert(.sleep)
            default: break
            }
        }
        return set
    }
}
