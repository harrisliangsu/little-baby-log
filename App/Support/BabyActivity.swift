import Foundation
import BabyLogKit

/// Work that is still bound to one baby. A switch must not retarget it.
@MainActor
final class BabyActivity: ObservableObject {
    @Published var formBabyID: UUID?
    @Published var recordingBabyID: UUID?
    @Published var aiBabyID: UUID?

    func beginForm(_ id: UUID?) {
        formBabyID = id
    }

    func endForm(_ id: UUID?) {
        guard formBabyID == id else { return }
        formBabyID = nil
    }

    func work() -> BabySwitch.Work? {
        let id = formBabyID ?? recordingBabyID ?? aiBabyID
        guard let id else { return nil }
        return BabySwitch.Work(
            babyID: id,
            unsavedForm: formBabyID == id,
            recording: recordingBabyID == id,
            aiInFlight: aiBabyID == id
        )
    }

    func clear() {
        formBabyID = nil
        recordingBabyID = nil
        aiBabyID = nil
    }
}
