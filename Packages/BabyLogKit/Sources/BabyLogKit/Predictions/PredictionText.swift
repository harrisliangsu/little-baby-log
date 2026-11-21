import Foundation

/// The words around a prediction, kept here so they are tested and the app and widgets agree.
public enum PredictionText {
    public static let disclaimer = "Estimates from typical ranges and your logs. Not medical advice."

    public static func disclaimer(_ language: ResolvedLanguage) -> String {
        switch language {
        case .zh: return "根据常见范围和你的记录估算。不是医疗建议。"
        case .en: return disclaimer
        }
    }

    public static func howItWorks(_ language: ResolvedLanguage) -> String {
        switch language {
        case .en: return howItWorks
        case .zh:
            return "宝宝醒着一段时间后通常会想睡，这段清醒时间会随月龄变长。一开始按月龄的常见清醒窗口估算。你记下睡眠之后，会慢慢混入这个宝宝自己最近的规律；大约十次相近的醒来之后，就主要跟着这个宝宝。入睡时间看来自平时的入睡时间和距离上一觉有多久。喂奶也一样，用最近几次的间隔，白天和夜里分开算。这些都在这台设备上根据记录算出来，不会发送出去。"
        }
    }

    public static let howItWorks = """
        Babies are usually ready to sleep after being awake for a while, and that "wake window" grows with age. \
        We start from typical wake windows for your baby's age. As you log sleeps, the app mixes in your baby's own \
        recent pattern, and after about ten matching wake-ups it mostly follows your baby. Bedtime is predicted from \
        your usual bedtime and how long since the last nap. Feeds work the same way, using the gaps between recent \
        feeds, with day and night counted separately. Everything is worked out on this device from your logs. Nothing \
        is sent anywhere.
        """

    /// "Based on Juniper's last 7 days" when the baby's own pattern dominates, "Typical for 7 weeks, tuned to
    /// Juniper's last 5 days" when mixed, "Typical for 7 weeks" when there is not enough history yet.
    public static func caption(basis: PredictionBasis, babyName: String, ageDays: Int, language: ResolvedLanguage = .en) -> String {
        let age = ageLabel(ageDays: ageDays, language: language)
        let days = lastDays
        switch (basis, language) {
        case (.typicalForAge, .zh):
            return "按\(age)的常见范围"
        case (.typicalForAge, .en):
            return "Typical for \(age)"
        case (.blended(let count), .zh):
            return "按\(age)的常见范围，并参考\(babyName)近 \(days(count)) 天"
        case (.blended(let count), .en):
            return "Typical for \(age), tuned to \(babyName)'s \(days(count) == 1 ? "last day" : "last \(days(count)) days")"
        case (.personal(let count), .zh):
            return "根据\(babyName)近 \(days(count)) 天"
        case (.personal(let count), .en):
            return "Based on \(babyName)'s \(days(count) == 1 ? "last day" : "last \(days(count)) days")"
        }
    }

    private static func lastDays(_ days: Int) -> Int {
        min(max(days, 1), SleepHistory.historyDays)
    }

    /// "newborns", "12 days", "7 weeks", "6 months", "2 years" (the largest unit that is at least 2, up to 12
    /// weeks and 24 months).
    public static func ageLabel(ageDays: Int, language: ResolvedLanguage = .en) -> String {
        let ageDays = max(0, ageDays)
        let months = Int((Double(ageDays) / 30.4375).rounded(.down))
        switch language {
        case .zh:
            if ageDays < 7 { return "新生儿" }
            if ageDays < 14 { return "\(ageDays) 天" }
            if ageDays < 84 { return "\(ageDays / 7) 周" }
            if months < 24 { return "\(months) 个月" }
            return "\(months / 12) 岁"
        case .en:
            if ageDays < 7 { return "newborns" }
            if ageDays < 14 { return "\(ageDays) days" }
            if ageDays < 84 { return "\(ageDays / 7) weeks" }
            if months < 24 { return "\(months) months" }
            return "\(months / 12) years"
        }
    }

    /// "2:10–2:40 PM" for a window, on the clock of `calendar`'s time zone and in `locale`'s style.
    public static func clockRange(of window: DateInterval, calendar: Calendar, locale: Locale) -> String {
        (window.start..<window.end).formatted(
            Date.IntervalFormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute()
        )
    }

    /// Where `now` stands against a prediction window.
    public enum Timing: Equatable, Sendable {
        case upcoming(TimeInterval)
        case now
        case overdue

        /// "in 25m", "in 1h 5m", "now", "overdue". Rounds up to whole minutes.
        public var text: String { labeled(.en) }

        public func labeled(_ language: ResolvedLanguage) -> String {
            switch (self, language) {
            case (.upcoming(let seconds), .en):
                let minutes = max(1, Int((seconds / 60).rounded(.up)))
                return "in " + DurationFormat.short(TimeInterval(minutes * 60))
            case (.upcoming(let seconds), .zh):
                let minutes = max(1, Int((seconds / 60).rounded(.up)))
                return DurationFormat.short(TimeInterval(minutes * 60)) + "后"
            case (.now, .en): return "now"
            case (.now, .zh): return "现在"
            case (.overdue, .en): return "overdue"
            case (.overdue, .zh): return "已过"
            }
        }
    }

    public static func timing(of window: DateInterval, at now: Date) -> Timing {
        if now < window.start { return .upcoming(window.start.timeIntervalSince(now)) }
        return now <= window.end ? .now : .overdue
    }
}
