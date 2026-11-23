import CoreData
import Foundation

/// A wet diaper save also writes one linked diaper change. Import and history replay do not call this.
public enum WetDiaperLink {
    public static let prefix = "lbl-wet-link:"

    public static func key(for wetID: UUID) -> String {
        prefix + wetID.uuidString
    }

    public static func isAutomatic(_ event: LogEvent) -> Bool {
        event.externalID?.hasPrefix(prefix) == true
    }

    public static func linked(to wetID: UUID, in context: NSManagedObjectContext) -> LogEvent? {
        let request = LogEvent.fetchRequest()
        request.predicate = NSPredicate(format: "externalID == %@", key(for: wetID))
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// New wet inserts one change. Editing a wet updates that change. An older wet with no link is not backfilled.
    /// A dirty or dry record does not create a wet record. Deleting the wet deletes only its linked change.
    public static func sync(event: LogEvent, isNew: Bool, in context: NSManagedObjectContext, now: Date = .now) {
        guard let wetID = event.uuid else { return }
        let existing = linked(to: wetID, in: context)
        let isWet = event.kind == .diaper && event.diaperKind == .wet
        guard isWet, let baby = event.baby else {
            if let existing { context.delete(existing) }
            return
        }
        if let existing {
            existing.kind = .diaper
            existing.diaperKind = .dry
            existing.startDate = event.startDate
            existing.baby = baby
            existing.modifiedAt = now
            return
        }
        guard isNew else { return }
        let change = LogEvent.create(kind: .diaper, for: baby, start: event.startDate ?? now, in: context)
        change.diaperKind = .dry
        change.externalID = key(for: wetID)
        change.modifiedAt = now
    }

    public static func deleteLinked(to event: LogEvent, in context: NSManagedObjectContext) {
        guard event.kind == .diaper, event.diaperKind == .wet, let id = event.uuid, let linked = linked(to: id, in: context) else { return }
        context.delete(linked)
    }
}
