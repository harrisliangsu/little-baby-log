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

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label(Copy.settings(language), systemImage: "gearshape.fill") }
            .tag(Tab.settings)
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

    private func refreshDay() {
        let today = Calendar.current.startOfDay(for: .now)
        if today != day { day = today }
    }
}

#Preview {
    MainTabView(baby: PreviewData.baby, link: .constant(nil))
        .previewEnvironment()
}
