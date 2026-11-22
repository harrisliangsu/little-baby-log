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
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var settingsPath: [SettingsRoute] = []
    @State private var assistantNotice = ""
    @State private var showChat = false
    @State private var chatVoice = false

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
                Button(action: voiceTapped) {
                    Image(systemName: "mic.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("voice-log")
                .accessibilityLabel(language == .zh ? "语音记录" : "Voice log")
            }
        }
        .sheet(isPresented: $showChat) {
            AIChatView(baby: baby, startVoice: chatVoice)
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

    private func voiceTapped() {
        switch AIRuntime.access() {
        case .ready:
            chatVoice = true
            showChat = true
        case .offline:
            assistantNotice = language == .zh ? "没有网络。" : "No network."
            openAssistant()
        case .missingCredential:
            let rejected = UserDefaults.standard.bool(forKey: AIPreferences.rejectedKey)
            assistantNotice = rejected ? (language == .zh ? "Key 不可用。" : "The key was rejected.") : ""
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

#Preview {
    MainTabView(baby: PreviewData.baby, link: .constant(nil))
        .previewEnvironment()
}
