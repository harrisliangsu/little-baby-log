import Foundation
import Testing
@testable import BabyLogKit

struct FormulaPreparedTests {
    @Test func preparedTotalsAreTheShortcutsAndWaterIsNot() {
        #expect(FormulaPreparedTable.milliliters == [65, 100, 130, 170, 200])
        #expect(FormulaPreparedTable.milliliters.count >= 4)
        #expect(!FormulaPreparedTable.milliliters.contains(60))
        #expect(!FormulaPreparedTable.milliliters.contains(11))
        #expect(!FormulaPreparedTable.milliliters.contains(41))
        #expect(FormulaPreparedTable.prefill(last: 130, pinned: nil) == 130)
        #expect(FormulaPreparedTable.prefill(last: 11, pinned: nil) == nil)
        #expect(FormulaPreparedTable.prefill(last: 11, pinned: 11) == 11)
        #expect(FormulaPreparedTable.prefill(last: nil, pinned: nil) == nil)
    }
}

struct VoiceCaptureTests {
    @Test func releaseEditsAndSwipeDiscardsWithoutSending() {
        var machine = VoiceCaptureMachine()
        #expect(machine.pressDown() == .beginCapture)
        #expect(machine.captureReady() == .none)
        #expect(machine.phase == .recording)
        #expect(machine.release() == .stopForEdit)
        machine.setTranscript("奶粉130")
        #expect(machine.confirm() == .send("奶粉130"))
        #expect(machine.confirm() == .none)

        #expect(machine.pressDown() == .beginCapture)
        _ = machine.captureReady()
        _ = machine.move(-80)
        #expect(machine.cancelArmed)
        #expect(machine.release() == .discard)
        #expect(machine.phase == .idle)
        #expect(machine.confirm() == .none)
    }

    @Test func deniedCaptureDoesNotSend() {
        var machine = VoiceCaptureMachine()
        _ = machine.pressDown()
        #expect(machine.captureDenied() == .discard)
        #expect(machine.phase == .denied)
        #expect(machine.confirm() == .none)
        #expect(machine.discardEdit() == .discard)
        #expect(machine.phase == .idle)
    }
}

struct AIStreamDecoderTests {
    @Test func sseDeltasAssembleAndJSONCompletionStaysSeparate() throws {
        let sse = """
        data: {"choices":[{"delta":{"content":"你好"}}]}

        data: {"choices":[{"delta":{"content":"，今天"}}]}

        data: [DONE]

        """
        #expect(AIStreamDecoder.assembledText(from: Data(sse.utf8), contentType: "text/event-stream") == "你好，今天")
        let completion = Data(#"{"choices":[{"message":{"content":"{\"text\":\"你好\"}"}}]}"#.utf8)
        #expect(AIStreamDecoder.assembledText(from: completion, contentType: "application/json") == nil)
        let shown = ChatSurface.present(#"{"text":"你好","items":[{"kind":"bottle","amountML":130}]}"#)
        #expect(shown.text == "你好")
        #expect(shown.records != nil)
        #expect(ChatSurface.present("我是记录解析助手，可以整理成 JSON").text.isEmpty)
        #expect(!ChatSurface.present("今天喝了奶粉").text.contains("JSON"))
    }
}
