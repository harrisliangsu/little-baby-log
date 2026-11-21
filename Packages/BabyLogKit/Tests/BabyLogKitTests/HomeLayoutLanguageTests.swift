import CoreData
import Foundation
import Testing
@testable import BabyLogKit

struct HomeLayoutLanguageTests {
    @Test func babiesKeepSeparateLayouts() {
        let ada = UUID()
        let bo = UUID()
        var data = HomeLayoutStore.save(BabyHomeLayout(preference: .formula), babyID: ada, into: nil)
        data = HomeLayoutStore.save(BabyHomeLayout(preference: .breast), babyID: bo, into: data)
        #expect(HomeLayoutStore.load(babyID: ada, from: data).preference == .formula)
        #expect(HomeLayoutStore.load(babyID: bo, from: data).preference == .breast)
        #expect(HomeLayoutStore.load(babyID: ada, from: data).cards == FeedPreference.formula.suggestedCards)
    }

    @Test func switchingPreferenceDoesNotHideRecordedCards() {
        var layout = BabyHomeLayout(preference: .formula)
        layout = layout.setting(.breast, visible: false)
        let resolved = layout.resolved(recorded: [.breast, .formula])
        #expect(resolved.contains(.breast))
        #expect(resolved.contains(.formula))
    }

    @Test func reorderAndHide() {
        var layout = BabyHomeLayout()
        layout = layout.moving(.formula, up: true)
        #expect(layout.cards.first == .formula)
        layout = layout.setting(.sleep, visible: false)
        #expect(!layout.cards.contains(.sleep))
        layout = layout.setting(.sleep, visible: true)
        #expect(layout.cards.last == .sleep)
    }

    @Test func chineseIsTheDefaultAndSystemCanBeEnglish() {
        #expect(AppLanguage.storedDefault == .zhHans)
        #expect(AppLanguage.zhHans.resolved() == .zh)
        #expect(AppLanguage.english.resolved() == .en)
        #expect(AppLanguage.system.resolved(preferredIdentifier: "en-US") == .en)
        #expect(AppLanguage.system.resolved(preferredIdentifier: "zh-Hans-CN") == .zh)
        #expect(Copy.card(.formula, .zh) == "奶粉")
        #expect(Copy.card(.formula, .en) == "Formula")
        #expect(Copy.ago(Date(timeIntervalSinceNow: -120), .en).contains("ago"))
        #expect(Copy.ago(Date(timeIntervalSinceNow: -120), .zh).contains("分钟前"))
    }

    @Test func timelineKeepsLateNightOnThatLocalDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 9))!
        let late = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 23, minute: 30))!
        #expect(TimelineRange.today.contains(now, now: now, calendar: calendar))
        #expect(!TimelineRange.today.contains(late, now: now, calendar: calendar))
        #expect(TimelineRange.yesterday.contains(late, now: now, calendar: calendar))
        #expect(TimelineRange.last7Days.contains(late, now: now, calendar: calendar))
        #expect(TimelineRange.all.contains(late, now: now, calendar: calendar))
    }
}

@MainActor
struct CloudTogglePersistenceTests {
    @Test func turningSyncOffKeepsTheSameRows() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("blk-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let when = TestSupport.utc(2026, 11, 21, 9)
        do {
            let local = PersistenceController(
                cloudKitContainerIdentifier: "iCloud.com.harrisliangsu.littlebabylog",
                cloudSyncEnabled: false,
                storeDirectory: dir
            )
            #expect(!local.isCloudSyncEnabled)
            let ctx = local.viewContext
            let baby = Baby.create(name: "月月", birthDate: when, in: ctx)
            let bottle = LogEvent.create(kind: .bottle, for: baby, start: when, in: ctx)
            bottle.amountML = 40
            bottle.bottleContent = .formula
            let nurse = LogEvent.create(kind: .breastfeed, for: baby, start: when.addingTimeInterval(-3600), in: ctx)
            nurse.leftSeconds = 480
            nurse.endDate = when.addingTimeInterval(-3000)
            #expect(ctx.saveIfNeeded())
        }
        let again = PersistenceController(
            cloudKitContainerIdentifier: "iCloud.com.harrisliangsu.littlebabylog",
            cloudSyncEnabled: false,
            storeDirectory: dir
        )
        let babies = try again.viewContext.fetch(Baby.fetchRequest())
        #expect(babies.count == 1)
        let events = try again.viewContext.fetch(LogEvent.requestAll(baby: babies[0]))
        #expect(events.count == 2)
        let care = CareRollup.make(events: events, now: when.addingTimeInterval(60), calendar: TestSupport.utcCalendar)
        #expect(care.today.formulaML == 40)
        #expect(care.lastFormulaML == 40)
        #expect(care.lastBreastSeconds == 480)
        #expect(care.today.formulaCount == 1)
    }
}
