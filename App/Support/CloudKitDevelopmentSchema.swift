import CoreData
import os
import BabyLogKit

/// Development-schema setup for NSPersistentCloudKitContainer.
///
/// Apple's documented path is `initializeCloudKitSchema` on a Debug build
/// (Creating a Core Data Model for CloudKit). It uploads representative records
/// to the development environment and then deletes them. It does not deploy
/// Production. CI never passes the launch flag, so tests do not call it.
enum CloudKitDevelopmentSchema {
    private static let log = Logger(subsystem: "app.littlebabylog", category: "cloudkit-schema")

    static func initializeIfRequested(_ persistence: PersistenceController) async {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-lbl-init-cloudkit-schema") else { return }
        let identifier = persistence.cloudKitContainerIdentifier ?? "iCloud.com.harrisliangsu.littlebabylog"
        // A fresh empty directory. The user's private.sqlite is not opened, so this
        // call does not mirror existing baby rows. Apple's initializer still uploads
        // temporary representative records and then deletes them.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lbl-cloudkit-schema-\(UUID().uuidString)", isDirectory: true)
        let empty = PersistenceController(
            cloudKitContainerIdentifier: identifier,
            storeDirectory: directory,
            cloudSyncEnabled: true
        )
        let deadline = Date().addingTimeInterval(30)
        while empty.privateStore == nil && empty.loadError == nil && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        defer {
            empty.closeStores()
            try? FileManager.default.removeItem(at: directory)
        }
        guard let cloud = empty.cloudKitContainer, empty.loadError == nil else {
            log.error("Schema init skipped: empty CloudKit store did not open")
            return
        }
        do {
            if arguments.contains("-lbl-cloudkit-schema-dry-run") {
                try cloud.initializeCloudKitSchema(options: [.dryRun])
            } else {
                try cloud.initializeCloudKitSchema()
            }
            log.notice("Development CloudKit schema initialization returned")
        } catch {
            log.error("Development schema initialization failed: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }
}
