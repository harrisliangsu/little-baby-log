import Foundation

/// Today and rolling-24-hour counts for the home cards and the widget snapshot.
///
/// Counts use each event's start. A feed or diaper logged yesterday evening is outside "today" and still
/// inside "24小时" until a full day has passed. Milk millilitres are formula bottles only. Pee is wet
/// (mixed counts too), poop is dirty (mixed counts too), and 换尿布 is a dry change.
public struct CareRollup: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
        public var formulaCount: Int
        public var formulaML: Double
        public var breastCount: Int
        public var wetCount: Int
        public var dirtyCount: Int
        public var diaperChangeCount: Int
        public var sleepCount: Int
        public var sleepSeconds: TimeInterval

        public init(
            formulaCount: Int = 0,
            formulaML: Double = 0,
            breastCount: Int = 0,
            wetCount: Int = 0,
            dirtyCount: Int = 0,
            diaperChangeCount: Int = 0,
            sleepCount: Int = 0,
            sleepSeconds: TimeInterval = 0
        ) {
            self.formulaCount = formulaCount
            self.formulaML = formulaML
            self.breastCount = breastCount
            self.wetCount = wetCount
            self.dirtyCount = dirtyCount
            self.diaperChangeCount = diaperChangeCount
            self.sleepCount = sleepCount
            self.sleepSeconds = sleepSeconds
        }

        public static let zero = Window()
    }

    public var today: Window
    public var last24Hours: Window
    /// Latest formula bottle. Nil when none has been logged.
    public var lastFormulaAt: Date?
    public var lastFormulaML: Double?
    /// End of the latest nursing session, or its start while the timer is still running.
    public var lastBreastAt: Date?
    /// Actual nursing duration. Never a made-up millilitre amount.
    public var lastBreastSeconds: TimeInterval?
    public var lastWetAt: Date?
    public var lastDirtyAt: Date?
    public var lastDiaperChangeAt: Date?
    /// End of the latest sleep, or its start while the baby is still asleep.
    public var lastSleepAt: Date?
    public var sleepRunning: Bool
    /// Latest feed of any kind (nursing or any bottle).
    public var lastFeedAt: Date?
    /// Latest diaper of any kind.
    public var lastDiaperAt: Date?

    public var hasAnyRecord: Bool {
        lastFeedAt != nil || lastDiaperAt != nil || lastSleepAt != nil
    }

    public init(
        today: Window = .zero,
        last24Hours: Window = .zero,
        lastFormulaAt: Date? = nil,
        lastFormulaML: Double? = nil,
        lastBreastAt: Date? = nil,
        lastBreastSeconds: TimeInterval? = nil,
        lastWetAt: Date? = nil,
        lastDirtyAt: Date? = nil,
        lastDiaperChangeAt: Date? = nil,
        lastSleepAt: Date? = nil,
        sleepRunning: Bool = false,
        lastFeedAt: Date? = nil,
        lastDiaperAt: Date? = nil
    ) {
        self.today = today
        self.last24Hours = last24Hours
        self.lastFormulaAt = lastFormulaAt
        self.lastFormulaML = lastFormulaML
        self.lastBreastAt = lastBreastAt
        self.lastBreastSeconds = lastBreastSeconds
        self.lastWetAt = lastWetAt
        self.lastDirtyAt = lastDirtyAt
        self.lastDiaperChangeAt = lastDiaperChangeAt
        self.lastSleepAt = lastSleepAt
        self.sleepRunning = sleepRunning
        self.lastFeedAt = lastFeedAt
        self.lastDiaperAt = lastDiaperAt
    }

    /// Events that start more than a minute ahead of `now` are ignored (the editor allows a tiny bit of clock skew).
    public static func make(events: [LogEvent], now: Date, calendar: Calendar = .current) -> CareRollup {
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86_400)
        let rollingStart = now.addingTimeInterval(-24 * 60 * 60)
        let horizon = now.addingTimeInterval(60)
        let todayInterval = DateInterval(start: startOfDay, end: endOfDay)
        let rollingInterval = DateInterval(start: rollingStart, end: horizon)

        var today = Window.zero
        var last24 = Window.zero
        var rollup = CareRollup()

        for event in events {
            guard let start = event.startDate, start <= horizon else { continue }
            switch event.kind {
            case .bottle:
                consider(start, current: &rollup.lastFeedAt)
                if event.bottleContent == .formula {
                    addCount(start, inToday: todayInterval, inRolling: rollingInterval) {
                        today.formulaCount += 1
                        today.formulaML += event.amountML
                    } rolling: {
                        last24.formulaCount += 1
                        last24.formulaML += event.amountML
                    }
                    if rollup.lastFormulaAt == nil || start > rollup.lastFormulaAt! {
                        rollup.lastFormulaAt = start
                        rollup.lastFormulaML = event.amountML
                    }
                }
            case .breastfeed:
                let reference = event.endDate ?? start
                consider(reference, current: &rollup.lastFeedAt)
                if rollup.lastBreastAt == nil || reference > rollup.lastBreastAt! {
                    rollup.lastBreastAt = reference
                    rollup.lastBreastSeconds = event.totalBreastSeconds(at: min(now, horizon))
                }
                addCount(start, inToday: todayInterval, inRolling: rollingInterval) {
                    today.breastCount += 1
                } rolling: {
                    last24.breastCount += 1
                }
            case .diaper:
                consider(start, current: &rollup.lastDiaperAt)
                switch event.diaperKind {
                case .wet:
                    addCount(start, inToday: todayInterval, inRolling: rollingInterval) {
                        today.wetCount += 1
                    } rolling: {
                        last24.wetCount += 1
                    }
                    consider(start, current: &rollup.lastWetAt)
                case .dirty:
                    addCount(start, inToday: todayInterval, inRolling: rollingInterval) {
                        today.dirtyCount += 1
                    } rolling: {
                        last24.dirtyCount += 1
                    }
                    consider(start, current: &rollup.lastDirtyAt)
                case .mixed:
                    addCount(start, inToday: todayInterval, inRolling: rollingInterval) {
                        today.wetCount += 1
                        today.dirtyCount += 1
                    } rolling: {
                        last24.wetCount += 1
                        last24.dirtyCount += 1
                    }
                    consider(start, current: &rollup.lastWetAt)
                    consider(start, current: &rollup.lastDirtyAt)
                case .dry:
                    addCount(start, inToday: todayInterval, inRolling: rollingInterval) {
                        today.diaperChangeCount += 1
                    } rolling: {
                        last24.diaperChangeCount += 1
                    }
                    consider(start, current: &rollup.lastDiaperChangeAt)
                case nil:
                    break
                }
            case .sleep:
                if event.isRunning { rollup.sleepRunning = true }
                let reference = event.endDate ?? start
                consider(reference, current: &rollup.lastSleepAt)
                addSleep(event, start: start, now: now, interval: todayInterval, horizon: horizon, into: &today)
                addSleep(event, start: start, now: now, interval: rollingInterval, horizon: horizon, into: &last24)
            default:
                break
            }
        }

        rollup.today = today
        rollup.last24Hours = last24
        return rollup
    }

    private static func consider(_ candidate: Date, current: inout Date?) {
        if let current, candidate <= current { return }
        current = candidate
    }

    private static func addCount(
        _ start: Date,
        inToday: DateInterval,
        inRolling: DateInterval,
        today addToday: () -> Void,
        rolling addRolling: () -> Void
    ) {
        if inToday.contains(start) { addToday() }
        if inRolling.contains(start) { addRolling() }
    }

    private static func addSleep(
        _ event: LogEvent,
        start: Date,
        now: Date,
        interval: DateInterval,
        horizon: Date,
        into window: inout Window
    ) {
        let end = min(event.endDate ?? now, now)
        let from = max(start, interval.start)
        let to = min(end, interval.end)
        if to > from { window.sleepSeconds += to.timeIntervalSince(from) }
        if interval.contains(start), start <= horizon {
            window.sleepCount += 1
        }
    }
}
