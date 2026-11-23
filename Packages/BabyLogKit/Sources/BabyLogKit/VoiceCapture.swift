import CoreGraphics
import Foundation

/// One recording gesture. The tab and the chat composer both drive this machine.
public struct VoiceCaptureMachine: Equatable {
    public enum Phase: Equatable {
        case idle
        case holding
        case recording
        case denied
        case interrupted
        case editing
    }

    public enum Effect: Equatable {
        case none
        case beginCapture
        case stopForEdit
        case discard
        case send(String)
    }

    public var phase: Phase
    public var cancelArmed: Bool
    public var partial: String
    public static let cancelDistance: CGFloat = 64

    public init() {
        phase = .idle
        cancelArmed = false
        partial = ""
    }

    public mutating func pressDown() -> Effect {
        switch phase {
        case .idle, .denied, .interrupted:
            phase = .holding
            cancelArmed = false
            partial = ""
            return .beginCapture
        case .holding, .recording, .editing:
            return .none
        }
    }

    public mutating func move(_ translationY: CGFloat) -> Effect {
        guard phase == .holding || phase == .recording else { return .none }
        cancelArmed = translationY < -Self.cancelDistance
        return .none
    }

    public mutating func captureReady() -> Effect {
        guard phase == .holding else { return .none }
        phase = .recording
        return .none
    }

    public mutating func captureDenied() -> Effect {
        guard phase == .holding || phase == .recording else { return .none }
        phase = .denied
        cancelArmed = false
        return .discard
    }

    public mutating func interrupted() -> Effect {
        guard phase == .holding || phase == .recording else { return .none }
        phase = .interrupted
        cancelArmed = false
        return .discard
    }

    /// Finger up. A swipe past the threshold discards. Otherwise the words wait for an explicit send.
    public mutating func release() -> Effect {
        let cancel = cancelArmed
        cancelArmed = false
        guard phase == .holding || phase == .recording else { return .none }
        if cancel {
            phase = .idle
            partial = ""
            return .discard
        }
        phase = .editing
        return .stopForEdit
    }

    public mutating func setTranscript(_ text: String) {
        guard phase == .editing else { return }
        partial = text
    }

    public mutating func confirm() -> Effect {
        guard phase == .editing else { return .none }
        let text = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .idle
        partial = ""
        guard !text.isEmpty else { return .none }
        return .send(text)
    }

    public mutating func discardEdit() -> Effect {
        switch phase {
        case .editing, .denied, .interrupted:
            phase = .idle
            partial = ""
            cancelArmed = false
            return .discard
        case .idle, .holding, .recording:
            return .none
        }
    }
}
