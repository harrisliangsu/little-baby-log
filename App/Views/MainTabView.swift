import SwiftUI
import UIKit
import BabyLogKit

struct MainTabView: View {
    let baby: Baby
    /// A deep link to act on. Any link brings Today forward; Today consumes it.
    @Binding var link: DeepLink?

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var desk: AIDesk
    @EnvironmentObject private var voice: VoiceSession
    @EnvironmentObject private var activity: BabyActivity
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var settingsPath: [SettingsRoute] = []
    @State private var assistantNotice = ""
    @State private var showChat = false
    @State private var showVoiceNotice = false
    @AppStorage(AIPreferences.voiceNoticeKey) private var voiceNoticeAck = false

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }
    @State private var tab: MainTab = .today

    var body: some View {
        ZStack {
            NavigationStack {
                TodayView(baby: baby, day: day, link: $link)
                    .id(day)
            }
            .modifier(DockPage(active: tab == .today))

            NavigationStack {
                HistoryView(baby: baby)
            }
            .modifier(DockPage(active: tab == .history))

            NavigationStack {
                TrendsView(baby: baby)
            }
            .modifier(DockPage(active: tab == .trends))

            NavigationStack(path: $settingsPath) {
                SettingsView()
                    .navigationDestination(for: SettingsRoute.self) { _ in
                        AISettingsView(notice: assistantNotice)
                    }
            }
            .modifier(DockPage(active: tab == .settings))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DockBar(tab: $tab, language: language, voice: voice, noticeAck: voiceNoticeAck, onNotice: {
                showVoiceNotice = true
            }) {
                openAssistantIfBlocked()
            }
        }
        .onChange(of: voice.isPresented) { _, shown in
            activity.recordingBabyID = shown ? baby.uuid : nil
        }
        .onChange(of: desk.pendingSend?.baby) { _, id in
            activity.aiBabyID = id
        }
        .overlay(alignment: .bottom) {
            if voice.isPresented {
                VoiceCapturePanel(voice: voice, language: language) { text in
                    sendVoice(text)
                }
                .padding(.bottom, 88)
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

    private func sendVoice(_ text: String) {
        guard let id = baby.uuid else { return }
        let message = desk.addDraft(baby: id, text: text)
        desk.notePending(baby: id, message: message)
        showChat = true
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

/// The dock chooses the visible page. A hidden system tab stayed on Settings after its button was tapped.
private struct DockPage: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 1 : 0)
            .accessibilityHidden(!active)
            .allowsHitTesting(active)
            .zIndex(active ? 1 : 0)
    }
}

#Preview {
    MainTabView(baby: PreviewData.baby, link: .constant(nil))
        .previewEnvironment()
        .environmentObject(AIDesk())
        .environmentObject(VoiceSession())
        .environmentObject(BabyActivity())
}
