import SwiftUI
import CoreData
import BabyLogKit

struct RootView: View {
    @Environment(\.persistence) private var persistence
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: Baby.lblAllByCreation()) private var babies: FetchedResults<Baby>
    @AppStorage(Prefs.selectedBabyID) private var selectedBabyID: String = ""
    /// A `littlebabylog://` link waiting for Today to act on it. Lives here, not in a tab, because
    /// switching babies rebuilds `MainTabView`.
    @State private var pendingLink: DeepLink?
    @State private var showMissingBaby = false
    @StateObject private var desk = AIDesk()
    @StateObject private var voice = VoiceSession()
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    private var selectedBaby: Baby? {
        babies.first(where: { $0.uuid?.uuidString == selectedBabyID }) ?? babies.first
    }

    var body: some View {
        Group {
            if let error = persistence.loadError {
                ContentUnavailableView {
                    Label(UICopy.t(.couldntOpen, L10n.resolved), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
            } else if let baby = selectedBaby {
                MainTabView(baby: baby, link: $pendingLink)
                    .environmentObject(desk)
                    .environmentObject(voice)
                    .onAppear { AIDesk.current = desk }
                    .id(baby.objectID)
            } else {
                OnboardingView { name, birthDate in
                    let baby = Baby.create(name: name, birthDate: birthDate, in: context)
                    context.saveIfNeeded()
                    selectedBabyID = baby.uuid?.uuidString ?? ""
                }
            }
        }
        .alert(Copy.missingBaby(language), isPresented: $showMissingBaby) {
            Button(language == .zh ? "知道了" : "OK", role: .cancel) {}
        }
        .background(alignment: .topLeading) { AppearanceSchemeProbe() }
        .task { await CloudKitDevelopmentSchema.initializeIfRequested(persistence) }
        .onOpenURL { url in
            if let link = DeepLink(url: url) { open(link) }
        }
        // A tapped reminder notification asks for Today (see `ReminderResponder`). The link may have been parked
        // before this view existed, so also look when it appears.
        .onReceive(NotificationCenter.default.publisher(for: DeepLinkRouter.didReceiveLink)) { _ in
            if let link = DeepLinkRouter.take() { open(link) }
        }
        .task {
            if let link = DeepLinkRouter.take() { open(link) }
        }
    }

    private func open(_ link: DeepLink) {
        let known = Set(babies.compactMap(\.uuid))
        guard !known.isEmpty else { return }
        guard StartRouting.knownBaby(link, knownBabyIDs: known) else {
            pendingLink = nil
            showMissingBaby = true
            return
        }
        if let id = link.babyID {
            selectedBabyID = id.uuidString
        }
        showMissingBaby = false
        pendingLink = link
    }
}

/// Reports the resolved color scheme so a test can wait for a real appearance change.
private struct AppearanceSchemeProbe: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Color.clear
            .frame(width: 4, height: 4)
            .accessibilityElement()
            .accessibilityIdentifier("appearance-scheme")
            .accessibilityLabel(scheme == .dark ? "dark" : "light")
            .allowsHitTesting(false)
    }
}

#Preview {
    RootView()
        .previewEnvironment()
}
