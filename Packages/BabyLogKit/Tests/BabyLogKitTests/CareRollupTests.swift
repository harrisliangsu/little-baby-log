import CoreData
import Foundation
import Testing
@testable import BabyLogKit

@MainActor
struct CareRollupTests {
    let calendar = TestSupport.utcCalendar
    /// 10:00 UTC, so yesterday evening is a different calendar day and still inside 24 hours.
    let now = TestSupport.utc(2026, 3, 10, 10)

    private func context() -> NSManagedObjectContext {
        TestSupport.makeContext().1
    }

    private func baby(_ ctx: NSManagedObjectContext) -> Baby {
        Baby.create(name: "Ada", birthDate: now, in: ctx)
    }

    private func tally(_ events: [LogEvent]) -> CareRollup {
        CareRollup.make(events: events, now: now, calendar: calendar)
    }

    @Test func emptyBabyIsZero() {
        let care = CareRollup.make(events: [], now: now, calendar: calendar)
        #expect(care.today == .zero)
        #expect(care.last24Hours == .zero)
        #expect(!care.hasAnyRecord)
        #expect(!care.sleepRunning)
        #expect(care.lastFormulaAt == nil)
        #expect(care.lastFeedAt == nil)
    }

    @Test func todayAndRolling24HoursStaySeparate() throws {
        let ctx = context()
        let baby = baby(ctx)

        let yesterdayEvening = LogEvent.create(kind: .bottle, for: baby, start: TestSupport.utc(2026, 3, 9, 23), in: ctx)
        yesterdayEvening.amountML = 30
        yesterdayEvening.bottleContent = .formula

        let thisMorning = LogEvent.create(kind: .bottle, for: baby, start: TestSupport.utc(2026, 3, 10, 9), in: ctx)
        thisMorning.amountML = 50
        thisMorning.bottleContent = .formula

        let tooOld = LogEvent.create(kind: .bottle, for: baby, start: TestSupport.utc(2026, 3, 9, 9), in: ctx)
        tooOld.amountML = 200
        tooOld.bottleContent = .formula

        let future = LogEvent.create(kind: .bottle, for: baby, start: TestSupport.utc(2026, 3, 10, 12), in: ctx)
        future.amountML = 80
        future.bottleContent = .formula

        let care = tally(try ctx.fetch(LogEvent.requestAll(baby: baby)))
        #expect(care.today.formulaCount == 1)
        #expect(care.today.formulaML == 50)
        #expect(care.last24Hours.formulaCount == 2)
        #expect(care.last24Hours.formulaML == 80)
        #expect(care.lastFormulaML == 50)
        #expect(care.lastFormulaAt == thisMorning.startDate)
    }

    @Test func formulaMillilitresIgnoreBreastMilk() throws {
        let ctx = context()
        let baby = baby(ctx)
        let formula = LogEvent.create(kind: .bottle, for: baby, start: now.addingTimeInterval(-3600), in: ctx)
        formula.amountML = 120
        formula.bottleContent = .formula
        let milk = LogEvent.create(kind: .bottle, for: baby, start: now.addingTimeInterval(-1800), in: ctx)
        milk.amountML = 90
        milk.bottleContent = .breastMilk

        let care = tally(try ctx.fetch(LogEvent.requestAll(baby: baby)))
        #expect(care.today.formulaCount == 1)
        #expect(care.today.formulaML == 120)
        #expect(care.last24Hours.formulaML == 120)
        #expect(care.lastFeedAt == milk.startDate)
        #expect(care.lastFormulaML == 120)
    }

    @Test func diapersSplitPeePoopAndChange() throws {
        let ctx = context()
        let baby = baby(ctx)
        func diaper(_ kind: DiaperKind, minutesAgo: Double) {
            let event = LogEvent.create(kind: .diaper, for: baby, start: now.addingTimeInterval(-minutesAgo * 60), in: ctx)
            event.diaperKind = kind
        }
        diaper(.wet, minutesAgo: 30)
        diaper(.dirty, minutesAgo: 50)
        diaper(.mixed, minutesAgo: 10)
        diaper(.dry, minutesAgo: 5)
        let yesterday = LogEvent.create(kind: .diaper, for: baby, start: TestSupport.utc(2026, 3, 9, 20), in: ctx)
        yesterday.diaperKind = .wet

        let care = tally(try ctx.fetch(LogEvent.requestAll(baby: baby)))
        #expect(care.today.wetCount == 2)
        #expect(care.today.dirtyCount == 2)
        #expect(care.today.diaperChangeCount == 1)
        #expect(care.last24Hours.wetCount == 3)
        #expect(care.last24Hours.dirtyCount == 2)
        #expect(care.last24Hours.diaperChangeCount == 1)
        #expect(care.lastDiaperAt == now.addingTimeInterval(-5 * 60))
    }

    @Test func updateAndDeleteChangeTheSnapshot() throws {
        let ctx = context()
        let baby = baby(ctx)
        let bottle = LogEvent.create(kind: .bottle, for: baby, start: now.addingTimeInterval(-600), in: ctx)
        bottle.amountML = 120
        bottle.bottleContent = .formula
        ctx.saveIfNeeded()

        var snapshot = WidgetSnapshot.make(
            babies: [baby], context: ctx, selectedBabyID: baby.uuid,
            volumeUnit: .milliliters, unitSystem: .metric, now: now
        )
        #expect(snapshot.babies.first?.care?.today.formulaML == 120)
        #expect(snapshot.babies.first?.name == "Ada")

        bottle.amountML = 90
        snapshot = WidgetSnapshot.make(
            babies: [baby], context: ctx, selectedBabyID: baby.uuid,
            volumeUnit: .milliliters, unitSystem: .metric, now: now
        )
        #expect(snapshot.babies.first?.care?.last24Hours.formulaML == 90)

        ctx.delete(bottle)
        ctx.saveIfNeeded()
        snapshot = WidgetSnapshot.make(
            babies: [baby], context: ctx, selectedBabyID: baby.uuid,
            volumeUnit: .milliliters, unitSystem: .metric, now: now
        )
        let care = try #require(snapshot.babies.first?.care)
        #expect(care.today.formulaCount == 0)
        #expect(care.last24Hours.formulaML == 0)
        #expect(!care.hasAnyRecord)
    }

    @Test func sleepCountAndRunningFlag() throws {
        let ctx = context()
        let baby = baby(ctx)
        let finished = LogEvent.create(kind: .sleep, for: baby, start: now.addingTimeInterval(-3 * 3600), in: ctx)
        finished.endDate = now.addingTimeInterval(-2 * 3600)
        let running = LogEvent.create(kind: .sleep, for: baby, start: now.addingTimeInterval(-20 * 60), in: ctx)

        let care = tally(try ctx.fetch(LogEvent.requestAll(baby: baby)))
        #expect(care.sleepRunning)
        #expect(care.today.sleepCount == 2)
        #expect(care.lastSleepAt == running.startDate)
        #expect(care.today.sleepSeconds > 3600)
    }
}
