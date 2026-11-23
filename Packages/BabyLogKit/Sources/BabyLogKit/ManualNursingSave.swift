import CoreData
import Foundation

/// What the nursing form does when Save is tapped.
///
/// The minute boxes keep their own text. That text can still say "1" while `leftSeconds` is 0:
/// the field has not resigned focus, or the binding has not caught up with the characters on screen.
/// Save has to read those characters. A draft that still looks like a running timer
/// (`endDate == nil`) otherwise passes validation and `apply` keeps the old zero duration.
public enum ManualNursingSave {
    public struct Fields: Equatable, Sendable {
        public var leftMinutesText: String
        public var rightMinutesText: String

        public init(leftMinutesText: String, rightMinutesText: String) {
            self.leftMinutesText = leftMinutesText
            self.rightMinutesText = rightMinutesText
        }
    }

    public enum Outcome: Equatable {
        case saved
        /// Validation failed. Nothing was inserted and the form must stay open.
        case rejected(String)
    }

    /// Leading number in a minute box. Blank is 0. "1分钟" is 1. Text with no number is nil.
    public static func minutes(fromDisplayed text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        var token = ""
        var seenSeparator = false
        for character in trimmed {
            if character.isNumber {
                token.append(character)
            } else if (character == "." || character == ",") && !seenSeparator && !token.isEmpty {
                seenSeparator = true
                token.append(".")
            } else if token.isEmpty, character.isWhitespace {
                continue
            } else {
                break
            }
        }
        guard let value = Double(token) else { return nil }
        return max(0, value)
    }

    /// An empty system field must not hide the "1" the form is already showing.
    public static func choosing(live: String?, mirror: String) -> String {
        let liveText = live ?? ""
        if (minutes(fromDisplayed: liveText) ?? 0) > 0 { return liveText }
        if (minutes(fromDisplayed: mirror) ?? 0) > 0 { return mirror }
        return liveText.isEmpty ? mirror : liveText
    }

    /// A shown minute replaces a binding that is still 0. Blank text does not erase seconds already stored.
    /// A positive duration finishes the session so `apply` cannot drop it as a running timer.
    public static func commit(fields: Fields, into draft: inout EventDraft) {
        if let minutes = minutes(fromDisplayed: fields.leftMinutesText), minutes > 0 {
            draft.leftSeconds = minutes * 60
        }
        if let minutes = minutes(fromDisplayed: fields.rightMinutesText), minutes > 0 {
            draft.rightSeconds = minutes * 60
        }
        if draft.leftSeconds + draft.rightSeconds > 0, draft.endDate == nil {
            draft.endDate = draft.startDate
        }
    }

    /// Inserts one nursing record for `baby` only after the displayed minutes are on the draft.
    /// A rejected save leaves the context unchanged.
    @discardableResult
    public static func save(
        draft: inout EventDraft,
        fields: Fields,
        baby: Baby,
        in context: NSManagedObjectContext,
        now: Date = .now
    ) -> Outcome {
        commit(fields: fields, into: &draft)
        if let message = draft.validationMessage {
            return .rejected(message)
        }
        let event = LogEvent.create(kind: .breastfeed, for: baby, start: draft.startDate, in: context)
        draft.apply(to: event, now: now)
        WetDiaperLink.sync(event: event, isNew: true, in: context, now: now)
        context.saveIfNeeded()
        return .saved
    }
}
