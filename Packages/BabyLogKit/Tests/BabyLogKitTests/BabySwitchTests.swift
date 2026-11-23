import Foundation
import Testing
@testable import BabyLogKit

struct BabySwitchTests {
    private let ada = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let bo = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    @Test func tapSelectsByIDAndIgnoresASameName() {
        let known: Set<UUID> = [ada, bo]
        #expect(BabySwitch.decide(stored: ada.uuidString, target: bo, known: known, work: nil) == .select(bo))
        #expect(BabySwitch.decide(stored: "贝贝", target: ada, known: known, work: nil) == .select(ada))
        #expect(BabySwitch.decide(stored: ada.uuidString, target: UUID(), known: known, work: nil) == nil)
    }

    @Test func openWorkOnTheCurrentBabyMustBeConfirmed() {
        let work = BabySwitch.Work(babyID: ada, unsavedForm: true)
        #expect(
            BabySwitch.decide(stored: ada.uuidString, target: bo, known: [ada, bo], work: work)
            == .confirmDiscard(from: ada, to: bo)
        )
        let recording = BabySwitch.Work(babyID: ada, recording: true)
        #expect(
            BabySwitch.decide(stored: ada.uuidString, target: bo, known: [ada, bo], work: recording)
            == .confirmDiscard(from: ada, to: bo)
        )
        let flight = BabySwitch.Work(babyID: ada, aiInFlight: true)
        #expect(
            BabySwitch.decide(stored: ada.uuidString, target: bo, known: [ada, bo], work: flight)
            == .confirmDiscard(from: ada, to: bo)
        )
    }

    @Test func idleOrOtherBabyWorkDoesNotBlock() {
        let idle = BabySwitch.Work(babyID: ada)
        #expect(BabySwitch.decide(stored: ada.uuidString, target: bo, known: [ada, bo], work: idle) == .select(bo))
        let elsewhere = BabySwitch.Work(babyID: bo, unsavedForm: true)
        #expect(BabySwitch.decide(stored: ada.uuidString, target: bo, known: [ada, bo], work: elsewhere) == .select(bo))
        #expect(BabySwitch.decide(stored: ada.uuidString, target: ada, known: [ada, bo], work: idle) == .select(ada))
    }

    @Test func configuredWidgetIgnoresTheAppSelection() {
        let snapshot = WidgetSnapshot(
            selectedBabyID: ada,
            babies: [
                WidgetSnapshot.BabySummary(id: ada, name: "贝贝"),
                WidgetSnapshot.BabySummary(id: bo, name: "贝贝"),
            ]
        )
        #expect(snapshot.baby(id: bo)?.id == bo)
        #expect(snapshot.baby(id: nil)?.id == ada)
        #expect(snapshot.baby(id: UUID())?.id == ada)
    }
}
