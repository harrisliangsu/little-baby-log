import SwiftUI
import UIKit
import BabyLogKit

struct MainTabView: View {
    let baby: Baby
    /// A deep link to act on. Any link brings Today forward; Today consumes it.
    @Binding var link: DeepLink?

    private enum Tab: Hashable {
        case today, history, trends, settings
    }

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var desk: AIDesk
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var settingsPath: [SettingsRoute] = []
    @State private var assistantNotice = ""
    @State private var showChat = false
    @State private var showVoiceNotice = false
    @State private var recording = false
    @State private var fingerDown = false
    @State private var cancelArmed = false
    @State private var holdTask: Task<Void, Never>?
    @StateObject private var speech = SpeechTranscriber()
    @AppStorage(AIPreferences.voiceNoticeKey) private var voiceNoticeAck = false

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }
    @State private var tab: Tab = .today

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                TodayView(baby: baby, day: day, link: $link)
                    .id(day)
            }
            .tabItem { Label(Copy.today(language), systemImage: "sun.max.fill") }
            .tag(Tab.today)

            NavigationStack {
                HistoryView(baby: baby)
            }
            .tabItem { Label(language == .zh ? "历史" : "History", systemImage: "calendar") }
            .tag(Tab.history)

            NavigationStack {
                TrendsView(baby: baby)
            }
            .tabItem { Label(language == .zh ? "趋势" : "Trends", systemImage: "chart.bar.fill") }
            .tag(Tab.trends)

            NavigationStack(path: $settingsPath) {
                SettingsView()
                    .navigationDestination(for: SettingsRoute.self) { _ in
                        AISettingsView(notice: assistantNotice)
                    }
            }
            .tabItem { Label(Copy.settings(language), systemImage: "gearshape.fill") }
            .tag(Tab.settings)
        }
        .safeAreaInset(edge: .bottom, spacing: 4) {
            // Reserve space under the list. An overlay on the tab view covered the last rows
            // and sat in the scroll gesture.
            ZStack {
                Color.clear
                    .frame(height: 64)
                    .allowsHitTesting(false)
                voiceButton
            }
        }
        .sheet(isPresented: $showChat) {
            AIChatView(baby: baby)
        }
        .sheet(isPresented: $showVoiceNotice) {
            VStack(alignment: .leading, spacing: 16) {
                Text(language == .zh
                     ? "语音会先由系统转成文字，可能会发给 Apple。转写后的文字会发给当前的 AI 供应商。录音不保留。"
                     : "Speech may go to Apple to become text. That text is sent to the current assistant. The recording is not kept.")
                Button(language == .zh ? "知道了" : "OK") {
                    voiceNoticeAck = true
                    showVoiceNotice = false
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("voice-notice-ok")
            }
            .padding(20)
            .presentationDetents([.height(220)])
        }
        .onChange(of: link, initial: true) { _, newLink in
            if newLink != nil { tab = .today }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshDay() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refreshDay()
        }
    }

    private var voiceButton: some View {
        VStack(spacing: 4) {
            if recording {
                Text(cancelArmed
                     ? (language == .zh ? "松开取消" : "Release to cancel")
                     : (language == .zh ? "松开生成" : "Release to send"))
                    .font(.caption.weight(.semibold))
            }
            Image(systemName: "mic.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Circle().fill(cancelArmed ? Color.red : Color.accentColor))
        }
        .contentShape(Rectangle())
        .gesture(voiceHold)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("voice-log")
        .accessibilityLabel(language == .zh ? "按住说话" : "Hold to talk")
    }

    private var voiceHold: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !fingerDown {
                    fingerDown = true
                    holdTask = Task { await armHold() }
                }
                cancelArmed = recording && value.translation.height < -48
            }
            .onEnded { _ in
                let wasRecording = recording
                fingerDown = false
                holdTask?.cancel()
                holdTask = nil
                let shouldCancel = cancelArmed
                cancelArmed = false
                if wasRecording {
                    recording = false
                    if shouldCancel {
                        speech.cancel()
                    } else {
                        Task { await releaseVoice() }
                    }
                } else {
                    // Too short to record. A closed or unready assistant still opens its settings.
                    openAssistantIfBlocked()
                }
            }
    }

    private func armHold() async {
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled, fingerDown else { return }
        switch AIRuntime.access() {
        case .ready:
            if !voiceNoticeAck {
                showVoiceNotice = true
                return
            }
            guard await speech.start() != nil else { return }
            guard fingerDown else {
                speech.cancel()
                return
            }
            recording = true
        default:
            openAssistantIfBlocked()
        }
    }

    /// A press that does not record. Ready assistants ignore it; every other state opens settings.
    private func openAssistantIfBlocked() {
        switch AIRuntime.access() {
        case .ready:
            break
        case .offline:
            assistantNotice = language == .zh ? "没有网络。" : "No network."
            openAssistant()
        case .missingCredential:
            assistantNotice = language == .zh ? "还不能使用。" : "The assistant is not ready."
            openAssistant()
        case .off:
            assistantNotice = ""
            openAssistant()
        }
    }

    private func releaseVoice() async {
        let text = await speech.stop()
        guard VoiceNextStep.after(stopped: true, transcript: text, failed: text == nil) == .preview,
              let spoken = text, let id = baby.uuid else { return }
        let message = desk.addDraft(baby: id, text: spoken)
        desk.notePending(baby: id, message: message)
        showChat = true
    }

    private func openAssistant() {
        showChat = false
        tab = .settings
        settingsPath = [.assistant]
    }

    private func refreshDay() {
        let today = Calendar.current.startOfDay(for: .now)
        if today != day { day = today }
    }
}

private enum SettingsRoute: Hashable {
    case assistant
}

#Preview {
    MainTabView(baby: PreviewData.baby, link: .constant(nil))
        .previewEnvironment()
        .environmentObject(AIDesk())
}
