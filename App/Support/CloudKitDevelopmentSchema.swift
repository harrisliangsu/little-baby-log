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
        print("LBL: Development CloudKit schema init started container=\(identifier)")
        print("LBL: schema init uses a temporary store, not the phone's private.sqlite")
        guard let cloud = empty.cloudKitContainer, empty.loadError == nil else {
            log.error("Schema init skipped: empty CloudKit store did not open")
            print("LBL: Development CloudKit schema initialization failed: temporary store did not open")
            return
        }
        let dryRun = arguments.contains("-lbl-cloudkit-schema-dry-run")
        let outcome: Result<Void, Error> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    if dryRun {
                        try cloud.initializeCloudKitSchema(options: [.dryRun])
                    } else {
                        try cloud.initializeCloudKitSchema()
                    }
                    continuation.resume(returning: .success(()))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
        switch outcome {
        case .success:
            log.notice("Development CloudKit schema initialization returned")
            print("LBL: Development CloudKit schema initialization returned")
        case .failure(let error):
            log.error("Development schema initialization failed: \(error.localizedDescription, privacy: .public)")
            print("LBL: Development CloudKit schema initialization failed: \(error.localizedDescription)")
        }
        #endif
    }
}
