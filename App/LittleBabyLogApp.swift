import SwiftUI
import CoreData
import BabyLogKit

@main
struct LittleBabyLogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @Environment(\.scenePhase) private var scenePhase
    @State private var gate = PersistenceGate()

    init() {
        let arguments = ProcessInfo.processInfo.arguments
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
                .id(ObjectIdentifier(gate.controller))
                .appearanceHost()
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Live Activities for timers that were already running (or arrived from a partner while
                    // the app wasn't in the foreground) can only be started now.
                    if phase == .active { Task { await AppServices.sceneDidBecomeActive() } }
                }
        }
    }
}
