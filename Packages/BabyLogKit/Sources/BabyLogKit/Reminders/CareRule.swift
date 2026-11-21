import Foundation

// One reminder rule per baby: a source record, how to turn it into a time, and the text to show.
// The app's existing ReminderPlanner schedules these beside the older feed/nap/daily settings.
// Rules live in ReminderSettingsStore (UserDefaults on this device). They are not part of the
// CloudKit store, so turning a rule on here does not make another phone fire it.

public struct RecordStamp: Equatable, Sendable {
    public var start: Date
    public var end: Date?

    public init(start: Date, end: Date? = nil) {
        self.start = start
        self.end = end
    }
}

public enum CareRuleSource: Codable, Equatable, Sendable {
    /// Nursing or a bottle, whichever is newer.
    case anyFeed
    /// One home card. Formula is bottle+formula only; nursing is its own card.
    case card(HomeCard)
    /// No log. An interval is measured from the last time someone marked the reminder done.
    /// Used for a caregiver's own target, such as drinking water. Not a record about the baby.
    case custom
}

public enum CareRuleTrigger: Codable, Equatable, Sendable {
    /// Measured from the latest matching record (or the last "done").
    case intervalSinceLast(minutes: Int, anchor: FeedIntervalAnchor)
    /// Measured from a source event, reminding about something else (a feed, then a caregiver drink).
    case delayAfterEvent(minutes: Int, anchor: FeedIntervalAnchor)
    /// A wall-clock time. The system notification follows the device time zone and daylight saving.
    case fixedTime(minutesOfDay: Int)
}

public struct CareRule: Codable, Equatable, Identifiable, Sendable {
    public static let minMinutes = 1
    public static let maxMinutes = 7 * 24 * 60
    /// Stable id for the single feed-interval setting migrated into a rule.
    public static let legacyFeedID = UUID(uuidString: "C0FFEE00-0000-4000-8000-0000000000F1")!

    public var id: UUID
    public var isEnabled: Bool
    public var title: String
    /// Notification title. The app supplies this from the user's words or a template.
    public var reminderText: String
    public var source: CareRuleSource
    public var trigger: CareRuleTrigger
    public var quietHours: QuietHours?
    /// Set when the person marks the reminder done without logging a new event.
    public var acknowledgedAt: Date?

    public init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        title: String = "",
        reminderText: String,
        source: CareRuleSource,
        trigger: CareRuleTrigger,
        quietHours: QuietHours? = nil,
        acknowledgedAt: Date? = nil
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.title = title
        self.reminderText = reminderText
        self.source = source
        self.trigger = trigger
        self.quietHours = quietHours
        self.acknowledgedAt = acknowledgedAt
    }

    public var clampedMinutes: Int? {
        switch trigger {
        case .intervalSinceLast(let minutes, _), .delayAfterEvent(let minutes, _):
            return min(max(minutes, Self.minMinutes), Self.maxMinutes)
        case .fixedTime:
            return nil
        }
    }
}

public enum CareRuleOutlook: Equatable, Sendable {
    case disabled
    /// Next fire. `repeatsDaily` is true when quiet hours are off, so the system can repeat at that clock time.
    case fires(Date, repeatsDaily: Bool)
    /// Nothing to measure from yet.
    case noBaseline
    /// The anchor is the end of a record that is still running.
    case waitingForEnd
    /// Marked done for the current source event. A newer event starts the delay again.
    case acknowledgedUntilNextRecord
    /// The interval already passed. A new record will schedule the next one. Nothing is pending.
    case overdue
}

public enum ReminderSchedulePolicy {
    /// Local notifications are capped by the system at 64 pending. Leave a few for snoozes.
    public static let pendingLimit = 60
    /// Rules and their pending notifications are scheduled on this device only.
    public static let syncsAcrossDevices = false
}

public enum CareRulePlanner {
    public static func outlook(
        rule: CareRule,
        baby: ReminderBaby,
        now: Date,
        calendar: Calendar
    ) -> CareRuleOutlook {
        guard rule.isEnabled else { return .disabled }
        switch rule.trigger {
        case .fixedTime(let minutes):
            guard let fire = nextFixed(minutesOfDay: minutes, after: now, quiet: rule.quietHours, notBefore: rule.acknowledgedAt, calendar: calendar) else {
                return .noBaseline
            }
            let repeats = rule.quietHours == nil && rule.acknowledgedAt == nil
            return .fires(fire, repeatsDaily: repeats)
        case .intervalSinceLast(let minutes, let anchor):
            switch baseline(rule: rule, baby: baby, anchor: anchor, delay: false) {
            case .missing: return .noBaseline
            case .waitingForEnd: return .waitingForEnd
            case .date(let start):
                let due = quiet(rule, start.addingTimeInterval(TimeInterval(clamped(minutes) * 60)), calendar)
                return due > now ? .fires(due, repeatsDaily: false) : .overdue
            }
        case .delayAfterEvent(let minutes, let anchor):
            switch baseline(rule: rule, baby: baby, anchor: anchor, delay: true) {
            case .missing: return .noBaseline
            case .waitingForEnd: return .waitingForEnd
            case .acknowledged: return .acknowledgedUntilNextRecord
            case .date(let start):
                let due = quiet(rule, start.addingTimeInterval(TimeInterval(clamped(minutes) * 60)), calendar)
                return due > now ? .fires(due, repeatsDaily: false) : .overdue
            }
        }
    }

    public static func requests(for baby: ReminderBaby, now: Date, calendar: Calendar) -> [ReminderRequest] {
        var seen = Set<UUID>()
        var result: [ReminderRequest] = []
        for rule in baby.settings.rules where seen.insert(rule.id).inserted {
            guard case .fires(let date, let repeats) = outlook(rule: rule, baby: baby, now: now, calendar: calendar) else { continue }
            result.append(request(rule: rule, baby: baby, fire: date, repeatsDaily: repeats))
        }
        return result
    }

    /// Round-robin across babies so one baby's rules cannot take every pending slot.
    public static func fairlyLimited(_ requests: [ReminderRequest], limit: Int = ReminderSchedulePolicy.pendingLimit) -> [ReminderRequest] {
        guard requests.count > limit, limit > 0 else { return requests }
        var order: [UUID] = []
        var buckets: [UUID: [ReminderRequest]] = [:]
        for request in requests {
            if buckets[request.babyID] == nil { order.append(request.babyID) }
            buckets[request.babyID, default: []].append(request)
        }
        var cursors = Dictionary(uniqueKeysWithValues: order.map { ($0, 0) })
        var result: [ReminderRequest] = []
        while result.count < limit {
            var progressed = false
            for baby in order {
                let index = cursors[baby] ?? 0
                guard let bucket = buckets[baby], index < bucket.count else { continue }
                result.append(bucket[index])
                cursors[baby] = index + 1
                progressed = true
                if result.count == limit { break }
            }
            if !progressed { break }
        }
        return result
    }

    // MARK: Baseline

    private enum Baseline: Equatable {
        case date(Date)
        case waitingForEnd
        case acknowledged
        case missing
    }

    private static func baseline(rule: CareRule, baby: ReminderBaby, anchor: FeedIntervalAnchor, delay: Bool) -> Baseline {
        if case .custom = rule.source {
            if delay { return .missing }
            if let acknowledged = rule.acknowledgedAt { return .date(acknowledged) }
            return .missing
        }
        guard let stamp = stamp(for: rule.source, baby: baby) else {
            if !delay, let acknowledged = rule.acknowledgedAt { return .date(acknowledged) }
            return .missing
        }
        let point: Date
        switch anchor {
        case .start:
            point = stamp.start
        case .end:
            if let end = resolvedEnd(stamp, source: rule.source) {
                point = max(end, stamp.start)
            } else {
                return .waitingForEnd
            }
        }
        if delay, let acknowledged = rule.acknowledgedAt, acknowledged >= point {
            return .acknowledged
        }
        if !delay, let acknowledged = rule.acknowledgedAt, acknowledged > point {
            return .date(acknowledged)
        }
        return .date(point)
    }

    /// The instant an interval or delay is measured from, when there is one.
    public static func measuredFrom(rule: CareRule, baby: ReminderBaby) -> Date? {
        let anchor: FeedIntervalAnchor
        let delay: Bool
        switch rule.trigger {
        case .intervalSinceLast(_, let value):
            anchor = value
            delay = false
        case .delayAfterEvent(_, let value):
            anchor = value
            delay = true
        case .fixedTime:
            return nil
        }
        if case .date(let date) = baseline(rule: rule, baby: baby, anchor: anchor, delay: delay) {
            return date
        }
        return nil
    }

    private static func stamp(for source: CareRuleSource, baby: ReminderBaby) -> RecordStamp? {
        switch source {
        case .anyFeed: return baby.anyFeed
        case .card(let card): return baby.stamps[card]
        case .custom: return nil
        }
    }

    /// Point events have no end. A missing end only means "still running" for nursing, sleep, and any feed.
    private static func resolvedEnd(_ stamp: RecordStamp, source: CareRuleSource) -> Date? {
        if let end = stamp.end { return end }
        switch source {
        case .anyFeed: return nil
        case .card(let card) where card == .breast || card == .sleep: return nil
        case .card, .custom: return stamp.start
        }
    }

    private static func quiet(_ rule: CareRule, _ date: Date, _ calendar: Calendar) -> Date {
        rule.quietHours?.firstAllowedMoment(atOrAfter: date, calendar: calendar) ?? date
    }

    private static func clamped(_ minutes: Int) -> Int {
        min(max(minutes, CareRule.minMinutes), CareRule.maxMinutes)
    }

    private static func nextFixed(
        minutesOfDay: Int,
        after now: Date,
        quiet: QuietHours?,
        notBefore: Date?,
        calendar: Calendar
    ) -> Date? {
        let clamped = min(max(minutesOfDay, 0), 1439)
        let hour = clamped / 60
        let minute = clamped % 60
        var day = calendar.startOfDay(for: now)
        for _ in 0..<8 {
            if let raw = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) {
                let fire = quiet?.firstAllowedMoment(atOrAfter: raw, calendar: calendar) ?? raw
                if fire > now, notBefore == nil || fire > notBefore! {
                    return fire
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
        }
        return nil
    }

    private static func request(rule: CareRule, baby: ReminderBaby, fire: Date, repeatsDaily: Bool) -> ReminderRequest {
        let text = rule.reminderText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = text.isEmpty ? "Reminder" : text
        var info = [
            ReminderUserInfoKey.babyID: baby.id.uuidString,
            ReminderUserInfoKey.ruleID: rule.id.uuidString,
        ]
        if let since = measuredFrom(rule: rule, baby: baby) {
            info[ReminderUserInfoKey.since] = String(since.timeIntervalSince1970)
        }
        if case .card(let card) = rule.source {
            info[ReminderUserInfoKey.card] = card.rawValue
        }
        let name = baby.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = name.isEmpty ? title : "\(name) · \(title)"
        let trigger: ReminderTrigger
        if repeatsDaily, case .fixedTime(let minutes) = rule.trigger {
            let clamped = min(max(minutes, 0), 1439)
            trigger = .daily(hour: clamped / 60, minute: clamped % 60)
        } else {
            trigger = .date(fire)
        }
        return ReminderRequest(
            identifier: ReminderIdentifier.rule(babyID: baby.id, ruleID: rule.id),
            babyID: baby.id,
            title: title,
            body: body,
            categoryIdentifier: ReminderCategory.rule,
            urgency: .timeSensitive,
            trigger: trigger,
            userInfo: info
        )
    }
}

public enum CareRuleTemplate {
    /// Every few hours after a feed. Covers nursing and bottles.
    public static func feedInterval(minutes: Int = 180, anchor: FeedIntervalAnchor = .start, text: String) -> CareRule {
        CareRule(
            reminderText: text,
            source: .anyFeed,
            trigger: .intervalSinceLast(minutes: minutes, anchor: anchor)
        )
    }

    /// After a feed, remind the caregiver about their own target (for example drinking water).
    /// The text is the user's. This is not a recommendation that the baby drink water.
    public static func caregiverAfterFeed(delayMinutes: Int = 30, text: String) -> CareRule {
        CareRule(
            reminderText: text,
            source: .anyFeed,
            trigger: .delayAfterEvent(minutes: delayMinutes, anchor: .end)
        )
    }

    public static func daily(minutesOfDay: Int = 9 * 60, text: String) -> CareRule {
        CareRule(
            reminderText: text,
            source: .custom,
            trigger: .fixedTime(minutesOfDay: minutesOfDay)
        )
    }
}
