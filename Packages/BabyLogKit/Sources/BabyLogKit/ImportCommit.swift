import CoreData
import Foundation

public struct ImportCommitResult: Equatable, Sendable {
    public var batchID: UUID
    public var inserted: Int
    public var skipped: Int
}

public struct ImportUndoResult: Equatable, Sendable {
    public var deleted: Int
    public var keptBecauseEdited: Int
}

public enum ImportCommit {
    /// Inserts the planned rows in one save. A failed save rolls the context back.
    /// Does not update or delete rows that were already there.
    public static func apply(
        file: ImportFile,
        plan: [PlannedImport],
        babies: [UUID: Baby],
        in context: NSManagedObjectContext,
        now: Date = Date()
    ) throws -> ImportCommitResult {
        let batchID = UUID()
        var inserted = 0
        var skipped = 0
        for item in plan {
            guard item.action == .insert, let babyID = item.babyID, let baby = babies[babyID],
                  let row = file.rows.first(where: { $0.line == item.line }),
                  let kind = row.field.kind, let start = row.field.start else {
                skipped += 1
                continue
            }
            let event = LogEvent.create(kind: kind, for: baby, start: start, in: context)
            var draft = EventDraft(kind: kind, now: start)
            draft.startDate = start
            draft.endDate = row.field.end
            draft.notes = row.field.notes
            draft.leftSeconds = row.field.leftSeconds
            draft.rightSeconds = row.field.rightSeconds
            if kind == .breastfeed, row.field.leftSeconds + row.field.rightSeconds == 0, let end = row.field.end {
                draft.rightSeconds = max(0, end.timeIntervalSince(start))
            }
            draft.amountML = row.field.amountML ?? 0
            draft.bottleContent = row.field.bottleContent ?? .formula
            draft.foodName = row.field.food
            draft.diaperKind = row.field.diaper ?? .wet
            draft.leftML = row.field.pumpedLeftML
            draft.rightML = row.field.pumpedRightML
            draft.weightKg = row.field.weightKg
            draft.lengthCm = row.field.lengthCm
            draft.headCm = row.field.headCm
            draft.medicineName = row.field.medicine
            draft.dose = row.field.dose
            if kind == .pump {
                draft.pumpDuration = max(0, (row.field.end ?? start).timeIntervalSince(start))
            }
            draft.apply(to: event, now: now)
            if kind == .sleep || kind == .pump {
                event.endDate = row.field.end
            }
            event.importBatchID = batchID
            event.externalID = row.field.externalId
            event.createdAt = now
            event.modifiedAt = now
            inserted += 1
        }
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
        return ImportCommitResult(batchID: batchID, inserted: inserted, skipped: skipped)
    }

    /// Deletes unedited rows from this batch. Edited rows and every other record stay.
    public static func undo(batchID: UUID, in context: NSManagedObjectContext) throws -> ImportUndoResult {
        let request = LogEvent.fetchRequest()
        let events = try context.fetch(request)
        var deleted = 0
        var kept = 0
        for event in events where event.importBatchID == batchID {
            if event.modifiedAt == event.createdAt {
                context.delete(event)
                deleted += 1
            } else {
                kept += 1
            }
        }
        if context.hasChanges { try context.save() }
        return ImportUndoResult(deleted: deleted, keptBecauseEdited: kept)
    }
}
