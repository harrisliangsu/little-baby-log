import CoreGraphics
import Foundation
import BabyLogKit

/// The only recording session. The dock and the chat composer both call it.
@MainActor
final class VoiceSession: ObservableObject {
    @Published private(set) var machine = VoiceCaptureMachine()
    @Published private(set) var level: Float = 0
    @Published var editorText = ""
    private let speech = SpeechTranscriber()

    var isPresented: Bool {
        switch machine.phase {
        case .idle: return false
        case .holding, .recording, .denied, .interrupted, .editing: return true
        }
    }

    func pressDown() {
        let effect = machine.pressDown()
        publish()
        guard effect == .beginCapture else { return }
        speech.onLevel = { [weak self] value in
            self?.level = value
        }
        Task { await begin() }
    }

    func move(_ translationY: CGFloat) {
        _ = machine.move(translationY)
        publish()
    }

    func release() {
        let effect = machine.release()
        publish()
        switch effect {
        case .stopForEdit:
            Task { await finishIntoEditor() }
        case .discard:
            speech.cancel()
            level = 0
            editorText = ""
        default:
            break
        }
    }

    func setTranscript(_ text: String) {
        machine.setTranscript(text)
        publish()
    }

    func confirm() -> String? {
        let effect = machine.confirm()
        publish()
        editorText = ""
        level = 0
        if case .send(let text) = effect { return text }
        return nil
    }

    func discard() {
        _ = machine.discardEdit()
        speech.cancel()
        level = 0
        editorText = ""
        publish()
    }

    private func begin() async {
        guard machine.phase == .holding else {
            speech.cancel()
            return
        }
        guard await speech.start() != nil else {
            _ = machine.captureDenied()
            level = 0
            publish()
            return
        }
        guard machine.phase == .holding else {
            speech.cancel()
            level = 0
            return
        }
        _ = machine.captureReady()
        publish()
    }

    private func finishIntoEditor() async {
        let text = await speech.stop() ?? ""
        level = 0
        editorText = text
        machine.setTranscript(text)
        publish()
    }

    private func publish() {
        machine = machine
    }
}
