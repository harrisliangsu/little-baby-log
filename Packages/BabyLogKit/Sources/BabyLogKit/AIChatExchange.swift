import CoreData
import Foundation

/// Turns a model body into the chat thread the screen shows.
/// A reply or a record card does not insert a log. Saving is a separate confirm.
public enum AIChatExchange {
    public static func apply(
        response: Data,
        to thread: AIChatThread,
        message id: UUID,
        anchor: VoiceAnchor,
        map: VoiceNameMap
    ) throws -> AIChatThread {
        switch try AIProposalDecoder.chatOutcome(from: response) {
        case .reply(let text):
            var copy = thread
            guard let index = copy.messages.firstIndex(where: { $0.id == id }) else { return copy }
            copy.messages[index].delivery = .sent
            copy.messages[index].records = []
            copy.messages.append(AIChatMessage(text: text, delivery: .sent))
            return copy
        case .records(let items):
            let records = VoiceDrafts.resolve(items: items, anchor: anchor, map: map)
            return thread.finishing(id, records: records)
        }
    }
}

/// The one write from a chat card into the log. The same card id cannot insert a second row.
public enum AIChatCommit {
    public static func externalID(for item: VoiceItemDraft) -> String {
        "ai-chat:" + item.id.uuidString
    }

    /// False when the card is incomplete, names a baby that is not in `babies`, or was already saved.
    @discardableResult
    public static func save(_ item: VoiceItemDraft, babies: [Baby], in context: NSManagedObjectContext) -> Bool {
        guard let draft = item.eventDraft() else { return false }
        guard let baby = babies.first(where: { $0.displayName == item.assignedBabyName }) else { return false }
        let key = externalID(for: item)
        let existing = LogEvent.fetchRequest()
        existing.predicate = NSPredicate(format: "externalID == %@", key)
        existing.fetchLimit = 1
        if let found = try? context.fetch(existing), !found.isEmpty { return false }
        let event = LogEvent.create(kind: draft.kind, for: baby, start: draft.startDate, in: context)
        draft.apply(to: event)
        event.externalID = key
        return context.saveIfNeeded()
    }
}
