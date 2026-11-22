import Foundation

/// How much of the chosen list a Home Screen size is allowed to show.
/// Small, medium, and large are different layouts. A size never draws a cut-off extra row.
public enum WidgetSize: String, Sendable {
    case small, medium, large

    /// Complete rows only. Extra picks stay off this size instead of shrinking the type.
    public var itemLimit: Int {
        switch self {
        case .small: 2
        case .medium: 4
        case .large: 6
        }
    }
}

/// One logged row the large widget can list. Amounts stay optional so pee never gains a made-up millilitre.
public struct RecentCare: Codable, Equatable, Sendable {
    public var card: HomeCard
    public var at: Date
    public var amountML: Double?
    public var duration: TimeInterval?
    public var times: Int?

    public init(card: HomeCard, at: Date, amountML: Double? = nil, duration: TimeInterval? = nil, times: Int? = nil) {
        self.card = card
        self.at = at
        self.amountML = amountML
        self.duration = duration
        self.times = times
    }

    public static func rows(from events: [LogEvent], now: Date) -> [RecentCare] {
        let horizon = now.addingTimeInterval(60)
        var rows: [RecentCare] = []
        for event in events {
            guard rows.count < 6 else { break }
            guard let start = event.startDate, start <= horizon, let card = HomeCardMatch.card(for: event) else { continue }
            var row = RecentCare(card: card, at: event.endDate ?? start)
            switch card {
            case .formula:
                row.amountML = event.amountML
            case .breast:
                row.duration = event.totalBreastSeconds(at: min(now, horizon))
            case .sleep:
                if let end = event.endDate { row.duration = max(0, end.timeIntervalSince(start)) }
            case .wet, .dirty, .diaperChange:
                row.times = 1
            }
            rows.append(row)
        }
        return rows
    }
}

/// The next reminder the user actually turned on. Absent when nothing is scheduled.
/// A nap prediction is not included: the widget does not invent a medical time.
public struct SnapshotReminder: Codable, Equatable, Sendable {
    public var text: String
    public var fireAt: Date
    /// False when the planner's title is a fixed English sentence. The widget then uses its own label.
    public var userWords: Bool

    public init(text: String, fireAt: Date, userWords: Bool) {
        self.text = text
        self.fireAt = fireAt
        self.userWords = userWords
    }
}

public enum SnapshotReminderPick {
    public static func next(for baby: ReminderBaby, now: Date, calendar: Calendar = .current) -> SnapshotReminder? {
        let requests = ReminderPlanner.requests(for: baby, now: now, calendar: calendar, locale: Locale(identifier: "en_US"))
        let soonest = requests.compactMap { request -> (Date, ReminderRequest)? in
            if request.identifier.contains(".nap.") { return nil }
            guard let fire = fireDate(of: request, after: now, calendar: calendar) else { return nil }
            return (fire, request)
        }.min { $0.0 < $1.0 }
        guard let soonest else { return nil }
        let request = soonest.1
        let userWords = request.identifier.contains(".rule.") || request.identifier.contains(".daily.")
        return SnapshotReminder(text: userWords ? request.title : "", fireAt: soonest.0, userWords: userWords)
    }

    private static func fireDate(of request: ReminderRequest, after now: Date, calendar: Calendar) -> Date? {
        switch request.trigger {
        case .date(let date):
            return date > now ? date : nil
        case .daily(let hour, let minute):
            var parts = DateComponents()
            parts.hour = hour
            parts.minute = minute
            return calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime)
        }
    }
}

public struct WidgetFaceItem: Equatable, Sendable {
    public var card: HomeCard
    public var title: String
    public var sinceLabel: String
    public var sinceValue: String
    public var lastLabel: String
    public var lastValue: String
    public var todayLabel: String
    public var todayValue: String
    public var dayLabel: String
    public var dayValue: String

    public var accessibilityText: String {
        [title, sinceLabel, sinceValue, lastLabel, lastValue, todayLabel, todayValue, dayLabel, dayValue]
            .joined(separator: " ")
    }
}

public struct WidgetFace: Equatable, Sendable {
    public var babyName: String
    public var items: [WidgetFaceItem]
    public var hiddenCount: Int
    public var limitNote: String?
    public var tapHint: String?
    public var recentTitle: String?
    public var recentLines: [String]
    public var reminderLine: String?
    public var missingBaby: String?
    public var chooseItems: String?
}

/// What a widget tap should open. Timeline links stay on the history screen and never come through here.
public enum WidgetComposerKind: Equatable, Sendable {
    case feedingChoice
    case editor(HomeCard)
}

public enum StartRouting {
    public static func knownBaby(_ link: DeepLink, knownBabyIDs: Set<UUID>) -> Bool {
        guard let id = link.babyID else { return true }
        return knownBabyIDs.contains(id)
    }

    public static func composer(for link: DeepLink) -> WidgetComposerKind? {
        guard case .start(let card, _) = link else { return nil }
        switch card {
        case .breast, .formula:
            return .editor(card)
        case .wet, .dirty, .diaperChange, .sleep:
            return .editor(card)
        }
    }
}

public enum WidgetBoard {
    public static func unique(_ cards: [HomeCard]) -> [HomeCard] {
        var seen = Set<HomeCard>()
        return cards.filter { seen.insert($0).inserted }
    }

    public static func fit(_ cards: [HomeCard], size: WidgetSize) -> (shown: [HomeCard], hidden: Int) {
        let ordered = unique(cards)
        let shown = Array(ordered.prefix(size.itemLimit))
        return (shown, ordered.count - shown.count)
    }

    public static func missing(language: ResolvedLanguage) -> WidgetFace {
        WidgetFace(
            babyName: "",
            items: [],
            hiddenCount: 0,
            limitNote: nil,
            tapHint: nil,
            recentTitle: nil,
            recentLines: [],
            reminderLine: nil,
            missingBaby: Copy.missingBaby(language),
            chooseItems: nil
        )
    }

    public static func face(
        babyName: String,
        care: CareRollup?,
        recent: [RecentCare],
        reminder: SnapshotReminder?,
        cards: [HomeCard],
        size: WidgetSize,
        language: ResolvedLanguage,
        volume: VolumeUnit,
        now: Date
    ) -> WidgetFace {
        let ordered = unique(cards)
        let fitted = fit(ordered, size: size)
        let items = fitted.shown.map { item($0, care: care, language: language, volume: volume, now: now) }
        let lines = size == .large ? recentLines(recent, cards: fitted.shown, language: language, volume: volume, now: now) : []
        let reminderText = size == .large ? reminderLine(reminder, language: language) : nil
        return WidgetFace(
            babyName: babyName,
            items: items,
            hiddenCount: fitted.hidden,
            limitNote: nil,
            tapHint: nil,
            recentTitle: size == .large && !lines.isEmpty ? Copy.recentRecords(language) : nil,
            recentLines: lines,
            reminderLine: reminderText,
            missingBaby: nil,
            chooseItems: ordered.isEmpty ? Copy.pickWidgetItems(language) : nil
        )
    }

    private static func item(
        _ card: HomeCard,
        care: CareRollup?,
        language: ResolvedLanguage,
        volume: VolumeUnit,
        now: Date
    ) -> WidgetFaceItem {
        let rollup = care ?? CareRollup()
        let none = Copy.none(language)
        let sinceDate: Date?
        let lastValue: String
        let today = rollup.today
        let day = rollup.last24Hours
        let todayCount: Int
        let todayExtra: String?
        let dayCount: Int
        let dayExtra: String?

        switch card {
        case .formula:
            sinceDate = rollup.lastFormulaAt
            lastValue = amount(rollup.lastFormulaML, recorded: sinceDate != nil, volume: volume, language: language) ?? none
            todayCount = today.formulaCount
            todayExtra = today.formulaML > 0 ? Copy.amount(today.formulaML, unit: volume, language) : nil
            dayCount = day.formulaCount
            dayExtra = day.formulaML > 0 ? Copy.amount(day.formulaML, unit: volume, language) : nil
        case .breast:
            sinceDate = rollup.lastBreastAt
            if let seconds = rollup.lastBreastSeconds, sinceDate != nil {
                lastValue = Copy.duration(seconds, language)
            } else {
                lastValue = none
            }
            todayCount = today.breastCount
            todayExtra = nil
            dayCount = day.breastCount
            dayExtra = nil
        case .wet:
            (sinceDate, lastValue, todayCount, todayExtra, dayCount, dayExtra) = countItem(
                rollup.lastWetAt, today.wetCount, day.wetCount, language: language
            )
        case .dirty:
            (sinceDate, lastValue, todayCount, todayExtra, dayCount, dayExtra) = countItem(
                rollup.lastDirtyAt, today.dirtyCount, day.dirtyCount, language: language
            )
        case .diaperChange:
            (sinceDate, lastValue, todayCount, todayExtra, dayCount, dayExtra) = countItem(
                rollup.lastDiaperChangeAt, today.diaperChangeCount, day.diaperChangeCount, language: language
            )
        case .sleep:
            sinceDate = rollup.lastSleepAt
            if rollup.sleepRunning {
                lastValue = Copy.sleeping(language)
            } else if sinceDate != nil {
                lastValue = Copy.count(1, language)
            } else {
                lastValue = none
            }
            todayCount = today.sleepCount
            todayExtra = today.sleepSeconds > 0 ? Copy.duration(today.sleepSeconds, language) : nil
            dayCount = day.sleepCount
            dayExtra = day.sleepSeconds > 0 ? Copy.duration(day.sleepSeconds, language) : nil
        }

        return WidgetFaceItem(
            card: card,
            title: Copy.card(card, language),
            sinceLabel: Copy.sinceLast(language),
            sinceValue: sinceDate.map { Copy.ago($0, now: now, language) } ?? none,
            lastLabel: Copy.lastAmount(language),
            lastValue: lastValue,
            todayLabel: Copy.todayWord(language),
            todayValue: joined(Copy.count(todayCount, language), todayExtra),
            dayLabel: Copy.last24(language),
            dayValue: joined(Copy.count(dayCount, language), dayExtra)
        )
    }

    private static func countItem(
        _ date: Date?,
        _ today: Int,
        _ day: Int,
        language: ResolvedLanguage
    ) -> (Date?, String, Int, String?, Int, String?) {
        let last = date == nil ? Copy.none(language) : Copy.count(1, language)
        return (date, last, today, nil, day, nil)
    }

    private static func amount(_ milliliters: Double?, recorded: Bool, volume: VolumeUnit, language: ResolvedLanguage) -> String? {
        guard recorded, let milliliters else { return nil }
        return Copy.amount(milliliters, unit: volume, language)
    }

    private static func joined(_ count: String, _ extra: String?) -> String {
        guard let extra else { return count }
        return "\(count) · \(extra)"
    }

    private static func recentLines(
        _ recent: [RecentCare],
        cards: [HomeCard],
        language: ResolvedLanguage,
        volume: VolumeUnit,
        now: Date
    ) -> [String] {
        recent.filter { cards.contains($0.card) }.prefix(4).map { row in
            var parts = [Copy.card(row.card, language), Copy.ago(row.at, now: now, language)]
            if let amount = row.amountML {
                parts.append(Copy.lastAmount(language) + " " + Copy.amount(amount, unit: volume, language))
            } else if let duration = row.duration {
                parts.append(Copy.lastAmount(language) + " " + Copy.duration(duration, language))
            } else if row.times != nil {
                parts.append(Copy.lastAmount(language) + " " + Copy.count(1, language))
            }
            return parts.joined(separator: " ")
        }
    }

    private static func reminderLine(_ reminder: SnapshotReminder?, language: ResolvedLanguage) -> String? {
        guard let reminder else { return nil }
        let words = reminder.userWords && !reminder.text.isEmpty ? reminder.text : Copy.setReminder(language)
        return "\(words) \(Copy.clock(reminder.fireAt, language))"
    }
}
