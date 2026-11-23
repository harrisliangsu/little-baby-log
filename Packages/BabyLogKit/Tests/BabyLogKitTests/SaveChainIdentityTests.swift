import Testing
import CoreData
@testable import BabyLogKit

/// The model chain only. This does not claim the on-screen form used the same draft.
@MainActor
struct SaveChainIdentityTests {
    @Test func oneMinuteSavedForOneBabyIsRereadByANewContext() throws {
        let (persistence, ctx) = TestSupport.makeContext()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let baby = Baby.create(name: "Beibei", birthDate: now, in: ctx)
        let other = Baby.create(name: "Other", birthDate: now, in: ctx)
        #expect(ctx.saveIfNeeded())
        let babyID = baby.uuid
        let otherID = other.uuid
        let editorContext = ObjectIdentifier(ctx)

        var draft = RecordDefaults.newDraft(kind: .breastfeed, events: [], now: now)
        #expect(draft.leftSeconds == 0)
        draft.leftSeconds = 60
        let outcome = ManualNursingSave.save(
            draft: &draft,
            fields: .init(leftMinutesText: "1", rightMinutesText: ""),
            baby: baby,
            in: ctx,
            now: now
        )
        #expect(outcome == .saved)
        #expect(ObjectIdentifier(ctx) == editorContext)

        let same = try ctx.fetch(LogEvent.requestAll(baby: baby, kinds: [.breastfeed]))
        #expect(same.count == 1)
        #expect(same[0].baby?.uuid == babyID)
        #expect(same[0].leftSeconds == 60)
        let sameRollup = CareRollup.make(events: same, now: now)
        #expect(sameRollup.lastBreastSeconds == 60)
        let otherRows = try ctx.fetch(LogEvent.requestAll(baby: other, kinds: [.breastfeed]))
        #expect(otherRows.isEmpty)

        let background = persistence.container.newBackgroundContext()
        let reread = background.performAndWait { () -> (count: Int, seconds: Double, baby: UUID?, others: Int) in
            let request = LogEvent.fetchRequest()
            let rows = (try? background.fetch(request)) ?? []
            let mine = rows.filter { $0.baby?.uuid == babyID }
            let others = rows.filter { $0.baby?.uuid == otherID && $0.kind == .breastfeed }.count
            return (mine.count, mine.first?.leftSeconds ?? -1, mine.first?.baby?.uuid, others)
        }
        #expect(reread.others == 0)
        #expect(reread.count == 1)
        #expect(reread.seconds == 60)
        #expect(reread.baby == babyID)
        #expect(ObjectIdentifier(background) != editorContext)
    }
}
