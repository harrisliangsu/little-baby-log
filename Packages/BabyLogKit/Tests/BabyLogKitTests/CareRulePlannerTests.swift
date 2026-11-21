import Foundation
import Testing
@testable import BabyLogKit

struct CareRulePlannerTests {
    private let babyID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let otherID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let utc = TestSupport.utcCalendar

    private func t(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        TestSupport.utc(2026, 6, day, hour, minute)
    }

    private func baby(
        id: UUID? = nil,
        settings: BabyReminderSettings,
        anyFeed: RecordStamp? = nil,
        stamps: [HomeCard: RecordStamp] = [:]
    ) -> ReminderBaby {
        ReminderBaby(
            id: id ?? babyID,
            name: "月月",
            settings: settings,
            lastFeed: nil,
            stamps: stamps,
            anyFeed: anyFeed
        )
    }

    @Test func intervalFromStartAndEnd() {
        let start = t(10, 8)
        let end = t(10, 8, 20)
        let feed = RecordStamp(start: start, end: end)
        let fromStart = CareRuleTemplate.feedInterval(minutes: 180, anchor: .start, text: "喂奶")
        let fromEnd = CareRuleTemplate.feedInterval(minutes: 90, anchor: .end, text: "喂奶")
        let startBaby = baby(settings: BabyReminderSettings(rules: [fromStart]), anyFeed: feed)
        let endBaby = baby(settings: BabyReminderSettings(rules: [fromEnd]), anyFeed: feed)
        let startPlan = CareRulePlanner.requests(for: startBaby, now: t(10, 8, 30), calendar: utc)
        let endPlan = CareRulePlanner.requests(for: endBaby, now: t(10, 8, 30), calendar: utc)
        #expect(startPlan.first?.fireDate == t(10, 11))
        #expect(endPlan.first?.fireDate == t(10, 9, 50))
        #expect(startPlan.count == 1)
        #expect(endPlan.count == 1)
    }

    @Test func runningFeedWaitsForEnd() {
        let rule = CareRuleTemplate.feedInterval(minutes: 30, anchor: .end, text: "喂奶")
        let running = baby(
            settings: BabyReminderSettings(rules: [rule]),
            anyFeed: RecordStamp(start: t(10, 8), end: nil)
        )
        #expect(CareRulePlanner.outlook(rule: rule, baby: running, now: t(10, 8, 10), calendar: utc) == .waitingForEnd)
        #expect(CareRulePlanner.requests(for: running, now: t(10, 8, 10), calendar: utc).isEmpty)
    }

    @Test func noBaselineIsExplainedAndNotScheduled() {
        let rule = CareRuleTemplate.feedInterval(minutes: 120, text: "喂奶")
        let empty = baby(settings: BabyReminderSettings(rules: [rule]))
        #expect(CareRulePlanner.outlook(rule: rule, baby: empty, now: t(10, 9), calendar: utc) == .noBaseline)
        #expect(CareRulePlanner.requests(for: empty, now: t(10, 9), calendar: utc).isEmpty)
    }

    @Test func loggingAgainMovesTheSameIdentifier() {
        let rule = CareRule(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            reminderText: "喂奶",
            source: .card(.formula),
            trigger: .intervalSinceLast(minutes: 180, anchor: .start)
        )
        let first = baby(
            settings: BabyReminderSettings(rules: [rule]),
            stamps: [.formula: RecordStamp(start: t(10, 5), end: t(10, 5))]
        )
        let second = baby(
            settings: BabyReminderSettings(rules: [rule]),
            stamps: [.formula: RecordStamp(start: t(10, 9), end: t(10, 9))]
        )
        let before = CareRulePlanner.requests(for: first, now: t(10, 6), calendar: utc)
        let after = CareRulePlanner.requests(for: second, now: t(10, 9, 30), calendar: utc)
        #expect(before.first?.identifier == after.first?.identifier)
        #expect(before.first?.fireDate == t(10, 8))
        #expect(after.first?.fireDate == t(10, 12))
        #expect(before.count == 1)
        #expect(after.count == 1)
    }

    @Test func disableDeletesTheRequestAndPassedIntervalIsNotPending() {
        var rule = CareRuleTemplate.feedInterval(minutes: 60, text: "喂奶")
        let stamped = baby(settings: BabyReminderSettings(rules: [rule]), anyFeed: RecordStamp(start: t(10, 8), end: t(10, 8)))
        #expect(CareRulePlanner.outlook(rule: rule, baby: stamped, now: t(10, 10), calendar: utc) == .overdue)
        rule.isEnabled = false
        let off = baby(settings: BabyReminderSettings(rules: [rule]), anyFeed: RecordStamp(start: t(10, 8), end: t(10, 8)))
        #expect(CareRulePlanner.outlook(rule: rule, baby: off, now: t(10, 8, 10), calendar: utc) == .disabled)
        #expect(CareRulePlanner.requests(for: off, now: t(10, 8, 10), calendar: utc).isEmpty)
    }

    @Test func quietHoursCrossMidnight() {
        var rule = CareRuleTemplate.feedInterval(minutes: 180, anchor: .start, text: "喂奶")
        rule.quietHours = QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60)
        let night = baby(settings: BabyReminderSettings(rules: [rule]), anyFeed: RecordStamp(start: t(10, 20), end: t(10, 20, 20)))
        let outlook = CareRulePlanner.outlook(rule: rule, baby: night, now: t(10, 21), calendar: utc)
        #expect(outlook == .fires(t(11, 7), repeatsDaily: false))
        let noon = baby(settings: BabyReminderSettings(rules: [rule]), anyFeed: RecordStamp(start: t(10, 10), end: t(10, 10)))
        #expect(CareRulePlanner.outlook(rule: rule, baby: noon, now: t(10, 11), calendar: utc) == .fires(t(10, 13), repeatsDaily: false))
    }

    @Test func fixedTimeUsesTheCalendarTimeZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let rule = CareRuleTemplate.daily(minutesOfDay: 9 * 60, text: "吃药")
        let person = baby(settings: BabyReminderSettings(rules: [rule]))
        var parts = DateComponents(timeZone: calendar.timeZone, year: 2026, month: 6, day: 10, hour: 8, minute: 30)
        let now = calendar.date(from: parts)!
        guard case .fires(let fire, let repeats) = CareRulePlanner.outlook(rule: rule, baby: person, now: now, calendar: calendar) else {
            Issue.record("expected a fire date")
            return
        }
        let shown = calendar.dateComponents([.hour, .minute], from: fire)
        #expect(shown.hour == 9)
        #expect(shown.minute == 0)
        #expect(repeats)
        let request = CareRulePlanner.requests(for: person, now: now, calendar: calendar).first
        #expect(request?.trigger == .daily(hour: 9, minute: 0))
    }

    @Test func intervalIsElapsedTimeAcrossDaylightSaving() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 3, day: 8, hour: 1, minute: 30))!
        let rule = CareRuleTemplate.feedInterval(minutes: 180, anchor: .start, text: "喂奶")
        let person = baby(settings: BabyReminderSettings(rules: [rule]), anyFeed: RecordStamp(start: start, end: start))
        let now = start.addingTimeInterval(60)
        guard case .fires(let fire, _) = CareRulePlanner.outlook(rule: rule, baby: person, now: now, calendar: calendar) else {
            Issue.record("expected a fire date")
            return
        }
        #expect(fire.timeIntervalSince(start) == 180 * 60)
        let wall = calendar.dateComponents([.hour, .minute], from: fire)
        #expect(wall.hour == 5)
        #expect(wall.minute == 30)
    }

    @Test func caregiverDelayDoesNotInventABaseline() {
        let rule = CareRuleTemplate.caregiverAfterFeed(delayMinutes: 30, text: "喝水")
        let waiting = baby(settings: BabyReminderSettings(rules: [rule]))
        #expect(CareRulePlanner.outlook(rule: rule, baby: waiting, now: t(10, 9), calendar: utc) == .noBaseline)
        let fed = baby(settings: BabyReminderSettings(rules: [rule]), anyFeed: RecordStamp(start: t(10, 8), end: t(10, 8, 15)))
        #expect(CareRulePlanner.outlook(rule: rule, baby: fed, now: t(10, 8, 20), calendar: utc) == .fires(t(10, 8, 45), repeatsDaily: false))
    }

    @Test func markDoneSuppressesUntilTheNextSourceEvent() {
        var rule = CareRuleTemplate.caregiverAfterFeed(delayMinutes: 20, text: "喝水")
        let feed = RecordStamp(start: t(10, 8), end: t(10, 8, 10))
        rule.acknowledgedAt = t(10, 8, 12)
        let done = baby(settings: BabyReminderSettings(rules: [rule]), anyFeed: feed)
        #expect(CareRulePlanner.outlook(rule: rule, baby: done, now: t(10, 8, 15), calendar: utc) == .acknowledgedUntilNextRecord)
        let later = RecordStamp(start: t(10, 12), end: t(10, 12, 5))
        let again = baby(settings: BabyReminderSettings(rules: [rule]), anyFeed: later)
        #expect(CareRulePlanner.outlook(rule: rule, baby: again, now: t(10, 12, 6), calendar: utc) == .fires(t(10, 12, 25), repeatsDaily: false))
    }

    @Test func rulesReplaceLegacyFeedRequests() {
        let legacy = FeedIntervalReminder(isEnabled: true, intervalMinutes: 120, anchor: .start)
        let rule = CareRuleTemplate.feedInterval(minutes: 180, text: "喂奶")
        let both = baby(
            settings: BabyReminderSettings(feedEvery: legacy, rules: [rule]),
            anyFeed: RecordStamp(start: t(10, 8), end: t(10, 8))
        )
        let planned = ReminderPlanner.plan(babies: [both], now: t(10, 8, 5), calendar: utc)
        #expect(planned.count == 1)
        #expect(planned.first?.identifier == ReminderIdentifier.rule(babyID: babyID, ruleID: rule.id))
        #expect(planned.allSatisfy { !$0.identifier.contains("feed.") })
    }

    @Test func adoptingRulesKeepsOneSchedule() {
        var settings = BabyReminderSettings(feedEvery: FeedIntervalReminder(isEnabled: true, intervalMinutes: 150, anchor: .end))
        settings.daily = [DailyReminder(minutesOfDay: 8 * 60, label: "维生素", kind: .medicine)]
        let adopted = settings.adoptingRules()
        #expect(!adopted.feedEvery.isEnabled)
        #expect(adopted.daily.isEmpty)
        #expect(adopted.rules.count == 2)
        #expect(adopted.adoptingRules() == adopted)
        let person = baby(settings: adopted, anyFeed: RecordStamp(start: t(10, 6), end: t(10, 6, 10)))
        let planned = ReminderPlanner.plan(babies: [person], now: t(10, 6, 20), calendar: utc)
        #expect(planned.count == 2)
        #expect(Set(planned.map(\.identifier)).count == 2)
    }

    @Test func fairCapKeepsEveryBaby() {
        func rules(_ count: Int) -> [CareRule] {
            (0..<count).map { index in
                CareRuleTemplate.daily(minutesOfDay: index % (20 * 60), text: "\(index)")
            }
        }
        let babies = [
            baby(id: babyID, settings: BabyReminderSettings(rules: rules(40))),
            baby(id: otherID, settings: BabyReminderSettings(rules: rules(40))),
        ]
        let planned = ReminderPlanner.plan(babies: babies, now: t(10, 0, 1), calendar: utc)
        #expect(planned.count == ReminderSchedulePolicy.pendingLimit)
        #expect(planned.contains { $0.babyID == babyID })
        #expect(planned.contains { $0.babyID == otherID })
        #expect(!ReminderSchedulePolicy.syncsAcrossDevices)
    }

    @Test func newerRecordMakesTheOldNotificationStale() {
        let rule = CareRule(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            reminderText: "喂奶",
            source: .anyFeed,
            trigger: .intervalSinceLast(minutes: 120, anchor: .start)
        )
        let firstFeed = RecordStamp(start: t(10, 8), end: t(10, 8))
        let person = baby(settings: BabyReminderSettings(rules: [rule]), anyFeed: firstFeed)
        let original = CareRulePlanner.requests(for: person, now: t(10, 8, 5), calendar: utc)[0]
        var moved = person
        moved.anyFeed = RecordStamp(start: t(10, 11), end: t(10, 11))
        #expect(ReminderPlanner.isStale(userInfo: original.userInfo, babies: [moved]))
        #expect(!ReminderPlanner.isStale(userInfo: original.userInfo, babies: [person]))
    }

    @Test func reminderSettingsStayInTheGivenDefaults() throws {
        let defaults = UserDefaults(suiteName: "care-rule-tests")!
        defaults.removePersistentDomain(forName: "care-rule-tests")
        let store = ReminderSettingsStore(defaults: defaults)
        var settings = BabyReminderSettings()
        settings.rules = [CareRuleTemplate.caregiverAfterFeed(text: "喝水")]
        store.save(settings, for: babyID)
        let other = UserDefaults(suiteName: "care-rule-tests-other")!
        other.removePersistentDomain(forName: "care-rule-tests-other")
        #expect(ReminderSettingsStore(defaults: other).settings(for: babyID).rules.isEmpty)
        let roundTrip = try JSONDecoder().decode(BabyReminderSettings.self, from: JSONEncoder().encode(store.settings(for: babyID)))
        #expect(roundTrip.rules.first?.reminderText == "喝水")
        #expect(roundTrip.rules.first?.source == .anyFeed)
    }
}
