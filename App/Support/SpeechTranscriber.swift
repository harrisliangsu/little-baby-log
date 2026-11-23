import AVFoundation
import Foundation
import Speech
import BabyLogKit

/// System speech-to-text. Buffers stay in memory for the recognizer and are not written to a file.
@MainActor
final class SpeechTranscriber: ObservableObject {
    @Published private(set) var partial = ""
    @Published private(set) var level: Float = 0
    var onLevel: ((Float) -> Void)?

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var generation = 0
    private var finished = false
    private var discarded = false
    private var tapInstalled = false

    /// Asks for speech and microphone permission, then starts. Returns nil when either is refused or the engine fails.
    func start() async -> VoiceAnchor? {
        stopEngine()
        generation += 1
        let token = generation
        discarded = false
        finished = false
        partial = ""
        guard await authorize(), token == generation else { return nil }
        let anchor = VoiceAnchor(startedAt: Date(), timeZone: .current)
        do {
            try startEngine(token: token)
            guard token == generation else { return nil }
            return anchor
        } catch {
            stopEngine()
            return nil
        }
    }

    func stop() async -> String? {
        let token = generation
        request?.endAudio()
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline, token == generation, !finished {
            try? await Task.sleep(for: .milliseconds(40))
        }
        let text = partial
        stopEngine()
        guard token == generation, !discarded else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func cancel() {
        generation += 1
        discarded = true
        partial = ""
        level = 0
        stopEngine()
    }

    /// 0 when the buffer has no samples. This is the live input level, not a fake animation.
    static func power(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?.pointee else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        let mean = sum / Float(count)
        guard mean > 0 else { return 0 }
        let decibels = 20 * log10(mean)
        return min(1, max(0, (decibels + 50) / 40))
    }

    private func authorize() async -> Bool {
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        let microphone = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        return microphone
    }

    private func startEngine(token: Int) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true)
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")) else {
            throw CocoaError(.featureUnsupported)
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CocoaError(.featureUnsupported) }
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            let power = Self.power(buffer)
            Task { @MainActor in
                guard self.generation == token, !self.discarded else { return }
                self.level = power
                self.onLevel?(power)
            }
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
        self.engine = engine
        self.request = request
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.generation == token, !self.discarded else { return }
                if let result {
                    self.partial = result.bestTranscription.formattedString
                    if result.isFinal { self.finished = true }
                }
                if error != nil { self.finished = true }
            }
        }
    }

    private func stopEngine() {
        if tapInstalled, let engine {
            engine.inputNode.removeTap(onBus: 0)
        }
        tapInstalled = false
        engine?.stop()
        request?.endAudio()
        recognition?.cancel()
        engine = nil
        request = nil
        recognition = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
