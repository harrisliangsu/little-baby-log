import Foundation

/// Who the app is showing, and what must not follow a switch.
///
/// Records, home cards, reminders, and per-baby defaults are stored by baby UUID.
/// Appearance, language, units, and assistant provider configuration belong to the device.
/// A switch changes only the selected UUID. It does not rewrite existing rows onto another baby.
public enum BabySwitch {
    public struct Work: Equatable, Sendable {
        public var babyID: UUID
        public var unsavedForm: Bool
        public var recording: Bool
        public var aiInFlight: Bool

        public var hasWork: Bool { unsavedForm || recording || aiInFlight }

        public init(babyID: UUID, unsavedForm: Bool = false, recording: Bool = false, aiInFlight: Bool = false) {
            self.babyID = babyID
            self.unsavedForm = unsavedForm
            self.recording = recording
            self.aiInFlight = aiInFlight
        }
    }

    public enum Decision: Equatable, Sendable {
        /// Become this baby. Open work, if any, is not bound to the baby being left.
        case select(UUID)
        /// Work is still bound to `from`. The caller must discard or keep it before selecting `to`.
        case confirmDiscard(from: UUID, to: UUID)
    }

    /// `stored` is the UUID string in preferences. Names are not accepted.
    /// Unknown targets are refused. The current baby with no open work selects again and writes nothing new.
    public static func decide(stored: String?, target: UUID, known: Set<UUID>, work: Work?) -> Decision? {
        guard known.contains(target) else { return nil }
        let current = stored.flatMap(UUID.init(uuidString:)).flatMap { known.contains($0) ? $0 : nil }
        if let work, let current, work.babyID == current, current != target, work.hasWork {
            return .confirmDiscard(from: current, to: target)
        }
        return .select(target)
    }
}
