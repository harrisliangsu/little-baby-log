import CoreData
import Foundation
import Testing
@testable import BabyLogKit

@MainActor
struct RecordDefaultTests {
    private func bottle(_ context: NSManagedObjectContext, _ baby: Baby, ml: Double, content: BottleContent, at: Date) -> LogEvent {
        let event = LogEvent.create(kind: .bottle, for: baby, start: at, in: context)
        event.amountML = ml
        event.bottleContent = content
        return event
    }

    @Test func formulaUsesThePreparedTotalAndTimeIsNow() throws {
        let (_, context) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: .now, in: context)
        _ = bottle(context, baby, ml: 11, content: .formula, at: Date().addingTimeInterval(-3600))
        _ = bottle(context, baby, ml: 130, content: .formula, at: Date().addingTimeInterval(-7200))
        let events = try context.fetch(LogEvent.fetchRequest())
        let now = Date()
        let draft = RecordDefaults.newDraft(kind: .bottle, bottle: .formula, events: events, now: now)
        #expect(draft.amountML == 0)
        let onlyOffTable = [bottle(context, baby, ml: 83, content: .formula, at: Date())]
        let off = RecordDefaults.newDraft(kind: .bottle, bottle: .formula, events: onlyOffTable, now: now)
        #expect(off.amountML == 0)
        let pinned = RecordDefaults.newDraft(kind: .bottle, bottle: .formula, events: onlyOffTable, now: now, formulaPin: 40)
        #expect(pinned.amountML == 40)
        #expect(abs(draft.startDate.timeIntervalSince(now)) < 2)
        #expect(draft.notes.isEmpty)
    }

    @Test func medicineKeepsTheNameAndDropsTheDose() throws {
        let (_, context) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: .now, in: context)
        let event = LogEvent.create(kind: .medicine, for: baby, start: .now, in: context)
        event.medicineName = "维生素"
        event.dose = "1 ml"
        let events = try context.fetch(LogEvent.fetchRequest())
        let draft = RecordDefaults.newDraft(kind: .medicine, events: events, now: .now)
        #expect(draft.medicineName == "维生素")
        #expect(draft.dose.isEmpty)
    }

    @Test func growthAndSleepDoNotCopyTheLastMeasurement() throws {
        let (_, context) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: .now, in: context)
        let growth = LogEvent.create(kind: .growth, for: baby, start: .now, in: context)
        growth.weightKg = 8
        growth.lengthCm = 70
        let sleep = LogEvent.create(kind: .sleep, for: baby, start: Date().addingTimeInterval(-8 * 3600), in: context)
        sleep.endDate = Date().addingTimeInterval(-6 * 3600)
        let events = try context.fetch(LogEvent.fetchRequest())
        let nextGrowth = RecordDefaults.newDraft(kind: .growth, events: events, now: .now)
        #expect(nextGrowth.weightKg == 0)
        #expect(nextGrowth.lengthCm == 0)
        let nextSleep = RecordDefaults.newDraft(kind: .sleep, events: events, now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(nextSleep.endDate == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(nextSleep.startDate == Date(timeIntervalSince1970: 1_800_000_000 - 3600))
    }
}
