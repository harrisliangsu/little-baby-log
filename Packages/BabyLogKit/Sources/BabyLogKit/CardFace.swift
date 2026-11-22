import Foundation

/// What one home card says. Basic is the latest core fact and how long ago it was.
/// Detail adds today's real totals for that type only. It never invents a zero.
public struct CardFace: Equatable, Sendable {
    public var primary: String
    public var detail: String?

    public init(primary: String, detail: String? = nil) {
        self.primary = primary
        self.detail = detail
    }
}

public enum CardFaces {
    public static func make(
        card: HomeCard,
        care: CareRollup,
        detailed: Bool,
        language: ResolvedLanguage,
        volume: VolumeUnit,
        now: Date
    ) -> CardFace {
        switch card {
        case .formula:
            return formula(care, detailed: detailed, language: language, volume: volume, now: now)
        case .breast:
            return breast(care, detailed: detailed, language: language, now: now)
        case .wet:
            return stamp(care.lastWetAt, todayCount: care.today.wetCount, detailed: detailed, language: language, now: now)
        case .dirty:
            return stamp(care.lastDirtyAt, todayCount: care.today.dirtyCount, detailed: detailed, language: language, now: now)
        case .diaperChange:
            return stamp(care.lastDiaperChangeAt, todayCount: care.today.diaperChangeCount, detailed: detailed, language: language, now: now)
        case .sleep:
            return sleep(care, detailed: detailed, language: language, now: now)
        }
    }

    private static func formula(
        _ care: CareRollup,
        detailed: Bool,
        language: ResolvedLanguage,
        volume: VolumeUnit,
        now: Date
    ) -> CardFace {
        let primary: String
        if let at = care.lastFormulaAt, let ml = care.lastFormulaML, ml > 0 {
            primary = joined(Copy.amount(ml, unit: volume, language), Copy.ago(at, now: now, language))
        } else {
            primary = Copy.none(language)
        }
        var extra: String?
        if detailed, care.today.formulaCount > 0 {
            extra = joined(Copy.count(care.today.formulaCount, language), Copy.amount(care.today.formulaML, unit: volume, language))
        }
        return CardFace(primary: primary, detail: extra)
    }

    private static func breast(
        _ care: CareRollup,
        detailed: Bool,
        language: ResolvedLanguage,
        now: Date
    ) -> CardFace {
        let primary: String
        if let at = care.lastBreastAt {
            if let seconds = care.lastBreastSeconds, seconds > 0 {
                primary = joined(Copy.duration(seconds, language), Copy.ago(at, now: now, language))
            } else {
                primary = Copy.ago(at, now: now, language)
            }
        } else {
            primary = Copy.none(language)
        }
        let extra = detailed && care.today.breastCount > 0 ? Copy.count(care.today.breastCount, language) : nil
        return CardFace(primary: primary, detail: extra)
    }

    private static func stamp(
        _ at: Date?,
        todayCount: Int,
        detailed: Bool,
        language: ResolvedLanguage,
        now: Date
    ) -> CardFace {
        let primary = at.map { Copy.ago($0, now: now, language) } ?? Copy.none(language)
        let extra = detailed && todayCount > 0 ? Copy.count(todayCount, language) : nil
        return CardFace(primary: primary, detail: extra)
    }

    private static func sleep(
        _ care: CareRollup,
        detailed: Bool,
        language: ResolvedLanguage,
        now: Date
    ) -> CardFace {
        let primary: String
        if care.sleepRunning, let at = care.lastSleepAt {
            primary = joined(Copy.sleeping(language), Copy.duration(now.timeIntervalSince(at), language))
        } else if let at = care.lastSleepAt {
            primary = Copy.ago(at, now: now, language)
        } else {
            primary = Copy.none(language)
        }
        var parts: [String] = []
        if detailed, care.today.sleepCount > 0 {
            parts.append(Copy.count(care.today.sleepCount, language))
        }
        if detailed, care.today.sleepSeconds > 0 {
            parts.append(Copy.duration(care.today.sleepSeconds, language))
        }
        return CardFace(primary: primary, detail: parts.isEmpty ? nil : parts.joined(separator: " · "))
    }

    private static func joined(_ first: String, _ second: String) -> String {
        "\(first) · \(second)"
    }
}

public enum LogTimeShortcut: Int, CaseIterable, Sendable {
    case now = 0
    case tenMinutes = 10
    case twentyMinutes = 20

    /// Anchored to `now` and the calendar, so twenty minutes before midnight is the previous day.
    public func date(from now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .minute, value: -rawValue, to: now) ?? now
    }
}

public enum AmountShortcuts {
    /// Nearby sizes when this baby has a real last amount. Otherwise common sizes, not a pretended last feed.
    /// `yesterdayRounded` is that baby's same bottle type, averaged over yesterday and raised to the next 10 ml.
    /// It is a logging shortcut, not a feeding recommendation. Missing days add nothing, including 0.
    public static func milliliters(around last: Double?, yesterdayRounded: Double? = nil) -> [Double] {
        var values: [Double] = []
        if let yesterdayRounded, let kept = positive(yesterdayRounded) {
            values.append(kept)
        }
        if let last, last > 0 {
            values.append(contentsOf: [last - 30, last, last + 30])
        } else {
            values.append(contentsOf: [60, 90, 120, 150])
        }
        return uniquePositive(values)
    }

    /// Smallest multiple of 10 ml that is still at least `average`. An exact ten stays put. 83 becomes 90.
    /// Zero, negative, and non-finite values return nil so the form does not offer 0 or NaN.
    public static func roundedUpToTen(_ average: Double) -> Double? {
        guard average.isFinite, average > 0 else { return nil }
        let scaled = average / 10
        let nearest = scaled.rounded()
        let steps = abs(scaled - nearest) < 0.000_001 ? nearest : scaled.rounded(.up)
        let value = steps * 10
        return positive(value)
    }

    /// Yesterday's local calendar day, for this baby and this bottle content only.
    /// Other babies, other contents, non-bottles, empty amounts, and deleted rows are left out.
    public static func yesterdayRoundedMilliliters(
        events: [LogEvent],
        baby: Baby,
        content: BottleContent,
        now: Date,
        calendar: Calendar
    ) -> Double? {
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) else { return nil }
        let amounts = events.compactMap { event -> Double? in
            guard !event.isDeleted else { return nil }
            guard event.baby?.objectID == baby.objectID else { return nil }
            guard event.kind == .bottle, event.bottleContent == content else { return nil }
            guard event.amountML.isFinite, event.amountML > 0 else { return nil }
            guard let date = event.startDate, date >= startOfYesterday, date < startOfToday else { return nil }
            return event.amountML
        }
        guard !amounts.isEmpty else { return nil }
        return roundedUpToTen(amounts.reduce(0, +) / Double(amounts.count))
    }

    private static func positive(_ value: Double) -> Double? {
        guard value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func uniquePositive(_ values: [Double]) -> [Double] {
        var seen = Set<Int>()
        var result: [Double] = []
        for value in values where value > 0 && value.isFinite {
            let key = Int(value.rounded())
            if seen.insert(key).inserted { result.append(value) }
        }
        return result
    }
}

public enum FormulaAmountSeed {
    /// Newest-first events for one baby. Only a positive formula bottle counts.
    public static func milliliters(newestFirst events: [LogEvent]) -> Double? {
        events.first { HomeCardMatch.matches($0, card: .formula) && $0.amountML > 0 }?.amountML
    }
}
