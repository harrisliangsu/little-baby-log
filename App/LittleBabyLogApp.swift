import SwiftUI
import CoreData
import BabyLogKit

@main
struct LittleBabyLogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @Environment(\.scenePhase) private var scenePhase
    @State private var gate = PersistenceGate()
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    /// Drives the window the same way Blinky does: one value on the scene, `nil` while following the system.
    /// Loaded after the UI-test reset so a previous launch cannot pin this process.
    @State private var appearanceMode: AppearanceMode

    init() {
        AppearanceMigration.apply(UserDefaults.standard)
        AIKeyStore.migrateLegacyConfigurations()
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        if arguments.contains("-lbl-ui-reset") {
            Self.resetInterfaceForUITest()
        }
        #endif
        if let index = arguments.firstIndex(of: "-lbl-language"), arguments.indices.contains(index + 1) {
            UserDefaults.standard.set(arguments[index + 1], forKey: AppLanguage.storageKey)
        }
        _appearanceMode = State(initialValue: ChromeSelection.load(from: .standard).mode)
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
                .preferredColorScheme(appearanceMode.colorScheme)
                .onReceive(NotificationCenter.default.publisher(for: .lblAppearanceModeChanged)) { note in
                    if let mode = note.object as? AppearanceMode {
                        appearanceMode = mode
                    }
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Live Activities for timers that were already running (or arrived from a partner while
                    // the app wasn't in the foreground) can only be started now.
                    guard phase == .active else { return }
                    ChromeBox.shared.noteSystem(ScreenStyle.current())
                    Task { await AppServices.sceneDidBecomeActive() }
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
