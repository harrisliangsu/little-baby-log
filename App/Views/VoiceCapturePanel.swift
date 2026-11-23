import SwiftUI
import BabyLogKit

/// Half-height recording panel. Levels come from the live buffer; a denied or idle capture stays flat.
struct VoiceCapturePanel: View {
    @ObservedObject var voice: VoiceSession
    let language: ResolvedLanguage
    let onSend: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(.secondary)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.2), Color.black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .background(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 8)
        .accessibilityIdentifier("voice-capture")
    }

    @ViewBuilder
    private var content: some View {
        switch voice.machine.phase {
        case .editing:
            editor
        case .denied:
            status(language == .zh ? "没有麦克风权限" : "Microphone permission was denied", "voice-denied")
        case .interrupted:
            status(language == .zh ? "录音中断了" : "Recording was interrupted", "voice-interrupted")
        case .holding, .recording, .idle:
            meter
        }
    }

    private var meter: some View {
        VStack(spacing: 18) {
            HStack(spacing: 6) {
                ForEach(0..<12, id: \.self) { index in
                    Circle()
                        .fill(voice.machine.cancelArmed ? Color.red : Color.white)
                        .frame(width: dot(index), height: dot(index))
                        .opacity(voice.machine.phase == .recording ? 1 : 0.35)
                }
            }
            .accessibilityIdentifier("voice-level")
            Text(caption)
                .font(.headline)
                .foregroundStyle(.white)
            if voice.machine.phase == .recording, voice.level < 0.04 {
                Text(language == .zh ? "没有收到声音" : "No sound yet")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Button(language == .zh ? "取消" : "Cancel") { voice.discard() }
                .foregroundStyle(.white)
                .accessibilityIdentifier("voice-discard")
        }
    }

    private var editor: some View {
        VStack(spacing: 12) {
            Text(language == .zh ? "转写可以改，确定后才发送" : "Edit the transcript, then send")
                .font(.subheadline.weight(.semibold))
            TextField(language == .zh ? "转写" : "Transcript", text: $voice.editorText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .accessibilityIdentifier("voice-transcript")
            HStack {
                Button(language == .zh ? "取消" : "Cancel") { voice.discard() }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .accessibilityIdentifier("voice-discard")
                Button(language == .zh ? "确定" : "Send") {
                    voice.setTranscript(voice.editorText)
                    if let text = voice.confirm() { onSend(text) }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 48)
                .accessibilityIdentifier("voice-send")
            }
        }
        .padding(.horizontal, 16)
    }

    private func status(_ text: String, _ identifier: String) -> some View {
        VStack(spacing: 12) {
            Text(text).font(.headline)
            Button(language == .zh ? "关闭" : "Close") { voice.discard() }
                .accessibilityIdentifier(identifier)
        }
    }

    private var caption: String {
        if voice.machine.cancelArmed {
            return language == .zh ? "松开撤回" : "Release to discard"
        }
        return language == .zh ? "松手编辑 · 上滑撤回" : "Release to edit · Swipe up to discard"
    }

    private func dot(_ index: Int) -> CGFloat {
        guard voice.machine.phase == .recording else { return 6 }
        let wave = abs(sin(Double(index) * 0.7))
        return 6 + CGFloat(voice.level) * 16 * CGFloat(wave)
    }
}
