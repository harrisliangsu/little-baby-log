import SwiftUI
import CoreData
import UIKit
import BabyLogKit

/// Settings > Reminders. Each baby has any number of rules, plus the existing nap-window estimate.
/// Rules live on this phone only. Edits go through `ReminderScheduler`, which replaces pending
/// notifications by identifier instead of stacking a second timer.
struct RemindersSettingsView: View {
    @FetchRequest(fetchRequest: Baby.lblAllByCreation()) private var babies: FetchedResults<Baby>
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appTheme) private var theme
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue

    @State private var permission: ReminderScheduler.Permission = .notDetermined

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    var body: some View {
        Form {
            if permission == .denied {
                permissionSection
            }
            ForEach(babies, id: \.objectID) { baby in
                if let id = baby.uuid {
                    CareRulesBabySection(
                        babyID: id,
                        babyName: baby.displayName,
                        showName: babies.count > 1,
                        permission: $permission
                    )
                }
            }
            Section {
            } footer: {
                Text(Copy.deviceReminders(language))
            }
        }
        .themedList()
        .navigationTitle(Copy.reminders(language))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            permission = await ReminderScheduler.shared.permission()
            ReminderScheduler.shared.registerCategories(language: language)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { permission = await ReminderScheduler.shared.permission() }
            }
        }
        .onChange(of: languageRaw) { _, _ in
            ReminderScheduler.shared.registerCategories(language: language)
        }
    }

    private var permissionSection: some View {
        Section {
            Label {
                Text(language == .zh ? "通知已关闭。" : "Notifications are off.")
            } icon: {
                Image(systemName: "bell.slash.fill")
                    .foregroundStyle(theme.isNight ? theme.destructive : .orange)
            }
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label(language == .zh ? "打开系统设置" : "Open Settings", systemImage: "gearshape.fill")
            }
        }
        .themedSection()
    }
}
