import SwiftUI
import CoreData
import BabyLogKit

@main
struct LittleBabyLogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @Environment(\.scenePhase) private var scenePhase
    @State private var gate = PersistenceGate()
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        if arguments.contains("-lbl-ui-reset") {
            Self.resetInterfaceForUITest()
        }
        #endif
        if let index = arguments.firstIndex(of: "-lbl-language"), arguments.indices.contains(index + 1) {
            UserDefaults.standard.set(arguments[index + 1], forKey: AppLanguage.storageKey)
        }
        AppServices.start()
        #if DEBUG
        DebugSampleHistory.seedIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, gate.controller.viewContext)
                .environment(\.persistence, gate.controller)
                .environment(gate)
                .environment(\.uiLanguage, (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved())
                .id(ObjectIdentifier(gate.controller))
                .appearanceHost()
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Live Activities for timers that were already running (or arrived from a partner while
                    // the app wasn't in the foreground) can only be started now.
                    if phase == .active { Task { await AppServices.sceneDidBecomeActive() } }
                }
        }
    }

    #if DEBUG
    /// Deletes the local store and snapshot so a later UI test starts from onboarding.
    private static func resetInterfaceForUITest() {
        if let identifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: identifier)
        }
        let files = FileManager.default
        if let directory = AppGroup.storeDirectory {
            try? files.removeItem(at: directory)
        }
        if let snapshot = AppGroup.snapshotURL {
            try? files.removeItem(at: snapshot)
        }
        let old = NSPersistentContainer.defaultDirectoryURL()
        for name in ["private.sqlite", "shared.sqlite", "widget-snapshot.json"] {
            try? files.removeItem(at: old.appendingPathComponent(name))
        }
    }
    #endif
}
