import Testing
import Foundation
@testable import BabyLogKit

@MainActor
struct ManualNursingSaveTests {
    /// The home card builds this draft: finished session, both sides still 0, until Save.
    private func cardDraft(now: Date) -> EventDraft {
        RecordDefaults.newDraft(kind: .breastfeed, events: [], now: now)
    }

    @Test func oneMinuteUsesTheSameFieldsTheFormSaves() throws {
        let (persistence, ctx) = TestSupport.makeContext()
        _ = persistence
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let baby = Baby.create(name: "Beibei", birthDate: now.addingTimeInterval(-86_400), in: ctx)
        var draft = cardDraft(now: now)
        // The minute row binds minutes, and the draft stores seconds.
        draft.leftSeconds = 1 * 60
        let outcome = ManualNursingSave.save(
            draft: &draft,
            fields: .init(leftMinutesText: "1", rightMinutesText: ""),
            baby: baby,
            in: ctx,
            now: now
        )
        #expect(outcome == .saved)
        let stored = try ctx.fetch(LogEvent.requestAll(baby: baby, kinds: [.breastfeed]))
        #expect(stored.count == 1)
        #expect(stored[0].baby?.objectID == baby.objectID)
        #expect(stored[0].leftSeconds == 60)
        #expect(stored[0].rightSeconds == 0)
        #expect(stored[0].duration(at: now) == 60)
        let care = CareRollup.make(events: stored, now: now)
        let face = CardFaces.make(card: .breast, care: care, detailed: false, language: .zh, volume: .milliliters, now: now)
        #expect(face.primary.contains("1分钟"))
        #expect(face.primary != Copy.none(.zh))
    }

    @Test func saveReadsTheMinuteTextWhileTheFieldStillHasFocus() throws {
        let (_, ctx) = TestSupport.makeContext()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let baby = Baby.create(name: "Beibei", birthDate: now, in: ctx)
        var draft = cardDraft(now: now)
        #expect(draft.leftSeconds == 0)
        // Focus has not ended, so Save is given the characters still in the box.
        let outcome = ManualNursingSave.save(
            draft: &draft,
            fields: .init(leftMinutesText: "1", rightMinutesText: ""),
            baby: baby,
            in: ctx,
            now: now
        )
        #expect(outcome == .saved)
        let stored = try ctx.fetch(LogEvent.requestAll(baby: baby, kinds: [.breastfeed]))
        #expect(stored.count == 1)
        #expect(stored[0].duration(at: now) == 60)
    }

    @Test func displayedOneMinuteOverridesABindingThatIsStillZero() throws {
        let (_, ctx) = TestSupport.makeContext()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let baby = Baby.create(name: "Beibei", birthDate: now, in: ctx)
        let other = Baby.create(name: "Other", birthDate: now, in: ctx)
        var draft = cardDraft(now: now)
        draft.leftSeconds = 0
        draft.rightSeconds = 0
        let outcome = ManualNursingSave.save(
            draft: &draft,
            fields: .init(leftMinutesText: "1", rightMinutesText: ""),
            baby: baby,
            in: ctx,
            now: now
        )
        #expect(outcome == .saved)
        let stored = try ctx.fetch(LogEvent.requestAll(baby: baby, kinds: [.breastfeed]))
        let elsewhere = try ctx.fetch(LogEvent.requestAll(baby: other, kinds: [.breastfeed]))
        #expect(stored.count == 1)
        #expect(elsewhere.isEmpty)
        #expect(stored[0].leftSeconds == 60)
        #expect(stored[0].duration(at: now) == 60)
        let care = CareRollup.make(events: stored, now: now)
        let face = CardFaces.make(card: .breast, care: care, detailed: false, language: .zh, volume: .milliliters, now: now)
        #expect(care.lastBreastSeconds == 60)
        #expect(face.primary.contains("1分钟"))
        #expect(!face.primary.contains(Copy.none(.zh)))
    }

    @Test func typedMinuteIsKeptWhenTheDraftStillLooksLikeARunningTimer() throws {
        let (_, ctx) = TestSupport.makeContext()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let baby = Baby.create(name: "Beibei", birthDate: now, in: ctx)
        var draft = EventDraft(kind: .breastfeed, now: now)
        draft.endDate = nil
        draft.leftSeconds = 0
        #expect(draft.isRunning)
        let outcome = ManualNursingSave.save(
            draft: &draft,
            fields: .init(leftMinutesText: "1", rightMinutesText: ""),
            baby: baby,
            in: ctx,
            now: now
        )
        #expect(outcome == .saved)
        let stored = try ctx.fetch(LogEvent.requestAll(baby: baby, kinds: [.breastfeed]))
        #expect(stored.count == 1)
        #expect(stored[0].duration(at: now) == 60)
        #expect(stored[0].endDate != nil)
    }

    @Test func emptyMinuteDoesNotInsert() throws {
        let (_, ctx) = TestSupport.makeContext()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let baby = Baby.create(name: "Beibei", birthDate: now, in: ctx)
        var draft = cardDraft(now: now)
        let outcome = ManualNursingSave.save(
            draft: &draft,
            fields: .init(leftMinutesText: "", rightMinutesText: ""),
            baby: baby,
            in: ctx,
            now: now
        )
        #expect(outcome != .saved)
        let stored = try ctx.fetch(LogEvent.requestAll(baby: baby, kinds: [.breastfeed]))
        #expect(stored.isEmpty)
        let face = CardFaces.make(
            card: .breast,
            care: CareRollup.make(events: stored, now: now),
            detailed: false,
            language: .zh,
            volume: .milliliters,
            now: now
        )
        #expect(face.primary == Copy.none(.zh))
    }
}
