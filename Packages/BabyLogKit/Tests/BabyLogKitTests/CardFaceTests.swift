import CoreData
import Foundation
import Testing
@testable import BabyLogKit

struct CardFaceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func basicFormulaIsAmountAndAgeWithoutTodaysTotal() {
        var care = CareRollup()
        care.lastFormulaAt = now.addingTimeInterval(-30)
        care.lastFormulaML = 120
        care.today.formulaCount = 2
        care.today.formulaML = 200
        let face = CardFaces.make(card: .formula, care: care, detailed: false, language: .zh, volume: .milliliters, now: now)
        #expect(face.primary.contains("120"))
        #expect(face.primary.contains("刚刚"))
        #expect(face.detail == nil)
        #expect(!face.primary.contains("2次"))
        #expect(!face.primary.contains("今日"))
    }

    @Test func detailFormulaAddsTodaysRealTotalOnly() {
        var care = CareRollup()
        care.lastFormulaAt = now.addingTimeInterval(-30)
        care.lastFormulaML = 120
        care.today.formulaCount = 2
        care.today.formulaML = 200
        let face = CardFaces.make(card: .formula, care: care, detailed: true, language: .zh, volume: .milliliters, now: now)
        #expect(face.detail?.contains("2次") == true)
        #expect(face.detail?.contains("200") == true)
        #expect(face.primary.contains("120"))
        #expect(!(face.detail ?? "").contains("今日"))
    }

    @Test func emptyDetailDoesNotInventAZero() {
        let face = CardFaces.make(card: .wet, care: CareRollup(), detailed: true, language: .zh, volume: .milliliters, now: now)
        #expect(face.primary == "还没有")
        #expect(face.detail == nil)
    }

    @Test func wetDetailIsACountAndBasicIsOnlyTheTime() {
        var care = CareRollup()
        care.lastWetAt = now.addingTimeInterval(-600)
        care.today.wetCount = 3
        let basic = CardFaces.make(card: .wet, care: care, detailed: false, language: .zh, volume: .milliliters, now: now)
        let detail = CardFaces.make(card: .wet, care: care, detailed: true, language: .zh, volume: .milliliters, now: now)
        #expect(basic.primary.contains("分钟前"))
        #expect(basic.detail == nil)
        #expect(!basic.primary.contains("3次"))
        #expect(detail.detail == "3次")
    }

    @Test func runningSleepShowsStatusAndElapsed() {
        var care = CareRollup()
        care.sleepRunning = true
        care.lastSleepAt = now.addingTimeInterval(-20 * 60)
        care.today.sleepCount = 1
        care.today.sleepSeconds = 20 * 60
        let face = CardFaces.make(card: .sleep, care: care, detailed: true, language: .zh, volume: .milliliters, now: now)
        #expect(face.primary.contains("睡眠中"))
        #expect(face.primary.contains("20分钟"))
        #expect(face.detail?.contains("1次") == true)
    }

    @Test func breastDoesNotShowMillilitres() {
        var care = CareRollup()
        care.lastBreastAt = now.addingTimeInterval(-120)
        care.lastBreastSeconds = 900
        care.today.breastCount = 1
        let face = CardFaces.make(card: .breast, care: care, detailed: true, language: .zh, volume: .milliliters, now: now)
        #expect(face.primary.contains("15分钟"))
        #expect(!face.primary.contains("ml"))
        #expect(face.detail == "1次")
    }
}

struct EntryChoiceTests {
    @Test func twentyMinutesBeforeMidnightIsThePreviousDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 0, minute: 5))!
        let earlier = LogTimeShortcut.twentyMinutes.date(from: now, calendar: calendar)
        #expect(calendar.component(.day, from: earlier) == 9)
        #expect(calendar.component(.hour, from: earlier) == 23)
        #expect(calendar.component(.minute, from: earlier) == 45)
        #expect(LogTimeShortcut.now.date(from: now, calendar: calendar) == now)
    }

    @Test func shortcutsUseTheLastAmountAndDoNotInventOne() {
        #expect(AmountShortcuts.milliliters(around: 120) == [90, 120, 150])
        #expect(AmountShortcuts.milliliters(around: nil) == [60, 90, 120, 150])
        #expect(AmountShortcuts.milliliters(around: 0) == [60, 90, 120, 150])
    }

    @MainActor
    @Test func formulaSeedStaysOnThisBabysFormula() throws {
        let (_, context) = TestSupport.makeContext()
        let ada = Baby.create(name: "Ada", birthDate: .now, in: context)
        let bo = Baby.create(name: "Bo", birthDate: .now, in: context)
        let breast = LogEvent.create(kind: .bottle, for: ada, start: Date(timeIntervalSince1970: 300), in: context)
        breast.bottleContent = .breastMilk
        breast.amountML = 50
        let older = LogEvent.create(kind: .bottle, for: ada, start: Date(timeIntervalSince1970: 100), in: context)
        older.bottleContent = .formula
        older.amountML = 80
        let latest = LogEvent.create(kind: .bottle, for: ada, start: Date(timeIntervalSince1970: 200), in: context)
        latest.bottleContent = .formula
        latest.amountML = 120
        let zero = LogEvent.create(kind: .bottle, for: ada, start: Date(timeIntervalSince1970: 400), in: context)
        zero.bottleContent = .formula
        zero.amountML = 0
        let other = LogEvent.create(kind: .bottle, for: bo, start: Date(timeIntervalSince1970: 500), in: context)
        other.bottleContent = .formula
        other.amountML = 999
        let adaEvents = try context.fetch(LogEvent.requestAll(baby: ada, kinds: [.bottle], ascending: false))
        let boEvents = try context.fetch(LogEvent.requestAll(baby: bo, kinds: [.bottle], ascending: false))
        #expect(FormulaAmountSeed.milliliters(newestFirst: adaEvents) == 120)
        #expect(FormulaAmountSeed.milliliters(newestFirst: boEvents) == 999)
    }
}

struct HomeCardPartitionTests {
    @Test func oldLayoutKeepsOrderAndStartsBasic() throws {
        let json = #"{"preference":"formula","cards":["formula","sleep"]}"#
        let layout = try JSONDecoder().decode(BabyHomeLayout.self, from: Data(json.utf8))
        #expect(layout.cards == [.formula, .sleep])
        #expect(layout.detailCards.isEmpty)
        #expect(layout.recordCards == [.formula, .sleep])
        #expect(layout.otherCards == [.breast, .wet, .dirty, .diaperChange])
        #expect(Set(layout.recordCards).isDisjoint(with: Set(layout.otherCards)))
    }

    @Test func detailFlagSurvivesARoundTripAndDoesNotReorder() throws {
        var layout = BabyHomeLayout(preference: .formula)
        let order = layout.cards
        layout = layout.settingDetail(.formula, detailed: true)
        let data = try JSONEncoder().encode(layout)
        let loaded = try JSONDecoder().decode(BabyHomeLayout.self, from: data)
        #expect(loaded.cards == order)
        #expect(loaded.isDetailed(.formula))
        #expect(!loaded.isDetailed(.sleep))
        #expect(loaded.settingDetail(.formula, detailed: false).detailCards.isEmpty)
    }
}
