import CoreData
import os
import BabyLogKit

extension PersistenceController {
    /// The app-wide store. CloudKit-backed when the build has a container identifier, otherwise local only.
    /// Lives in the App Group container (so it's next to the widget snapshot), migrated once from the old
    /// default location. Falls back to the default location if the group isn't available.
    static var shared: PersistenceController { ActivePersistence.current }

    static var storedCloudSyncEnabled: Bool {
        if UserDefaults.standard.object(forKey: Prefs.cloudSyncEnabled) == nil { return true }
        return UserDefaults.standard.bool(forKey: Prefs.cloudSyncEnabled)
    }

    static func makeAppStore(cloudSyncEnabled: Bool) -> PersistenceController {
        PersistenceController(
            cloudKitContainerIdentifier: AppConfig.cloudKitContainerIdentifier,
            storeDirectory: appGroupStoreDirectory(),
            cloudSyncEnabled: cloudSyncEnabled
        )
    }

    /// In-memory store filled with sample data, for SwiftUI previews.
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        SampleData.populate(controller.viewContext)
        return controller
    }()

    /// `<App Group>/Library/Application Support`, after moving an existing store there. nil means "use the
    /// default directory": the group is unavailable, or the migration failed and the old store is still the
    /// only copy (it will be retried on the next launch).
    private static func appGroupStoreDirectory() -> URL? {
        let log = Logger(subsystem: "app.littlebabylog", category: "storage")
        guard let directory = AppGroup.storeDirectory else {
            log.error("App Group container unavailable; using the default store location")
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            log.error("Couldn't create the group store directory: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let old = NSPersistentContainer.defaultDirectoryURL()
        if !StoreMigration.migrateIfNeeded(from: old, to: directory) {
            let oldStillHoldsData = FileManager.default.fileExists(atPath: old.appendingPathComponent("private.sqlite").path)
            let newIsEmpty = !FileManager.default.fileExists(atPath: directory.appendingPathComponent("private.sqlite").path)
            if oldStillHoldsData && newIsEmpty {
                log.error("Store migration failed; staying on the old location for now")
                return nil
            }
        }
        return directory
    }
}

enum ActivePersistence {
    private(set) static var current = PersistenceController.makeAppStore(
        cloudSyncEnabled: PersistenceController.storedCloudSyncEnabled
    )

    /// Closes the open store and opens it again. The sqlite file is not copied or deleted.
    static func replace(cloudSyncEnabled: Bool) -> PersistenceController {
        current.closeStores()
        UserDefaults.standard.set(cloudSyncEnabled, forKey: Prefs.cloudSyncEnabled)
        let next = PersistenceController.makeAppStore(cloudSyncEnabled: cloudSyncEnabled)
        current = next
        return next
    }
}

extension Baby {
    /// All babies, oldest first. Used with `@FetchRequest(fetchRequest:)`.
    static func lblAllByCreation() -> NSFetchRequest<Baby> {
        let request: NSFetchRequest<Baby> = Baby.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return request
    }
}
