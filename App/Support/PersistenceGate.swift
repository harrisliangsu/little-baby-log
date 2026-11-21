import SwiftUI
import BabyLogKit

/// Owns the store the interface is showing. Turning iCloud on or off closes that store and
/// opens the same `private.sqlite` again, with or without CloudKit. Rows are not copied or deleted.
@MainActor
@Observable
final class PersistenceGate {
    private(set) var controller: PersistenceController
    private let allowsReplacement: Bool

    init(controller: PersistenceController? = nil, allowsReplacement: Bool = true) {
        self.controller = controller ?? ActivePersistence.current
        self.allowsReplacement = allowsReplacement && controller == nil
    }

    var cloudSyncEnabled: Bool { controller.isCloudSyncEnabled }

    var canToggle: Bool { AppConfig.cloudKitContainerIdentifier != nil }

    func setCloudSync(_ enabled: Bool) {
        guard allowsReplacement, enabled != controller.isCloudSyncEnabled else { return }
        let next = ActivePersistence.replace(cloudSyncEnabled: enabled)
        AppServices.restart(persistence: next)
        controller = next
    }
}
