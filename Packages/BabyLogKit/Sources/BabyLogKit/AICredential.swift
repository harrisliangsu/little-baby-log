import Foundation

/// A connection check. It names the model and carries no baby data.
public enum AIProbe {
    public static let userText = "Return json {\"ok\":true}."
}

public struct AIVerifyStamp: Equatable, Sendable {
    public var provider: String
    public var model: String
    public var lastFour: String

    public init(provider: String, model: String, lastFour: String) {
        self.provider = provider
        self.model = model
        self.lastFour = lastFour
    }
}

public enum AIVerifyStatus: Equatable, Sendable {
    case checking
    case verified
    case rejected
    case offline
    case unavailable
}

public struct AIVerifyRecord: Equatable, Sendable {
    public var stamp: AIVerifyStamp
    public var status: AIVerifyStatus

    public init(stamp: AIVerifyStamp, status: AIVerifyStatus) {
        self.stamp = stamp
        self.status = status
    }
}

public enum AICredentialPhase: Equatable, Sendable {
    case unconfigured
    case savedUnverified
    case checking
    case verified
    case rejected
    case offline
    case unavailable
}

public enum AICredentialState {
    /// A saved key with no matching check is not treated as connected.
    /// A check for another provider, model, or key suffix does not count.
    public static func phase(hasKey: Bool, current: AIVerifyStamp, record: AIVerifyRecord?) -> AICredentialPhase {
        guard hasKey else { return .unconfigured }
        guard let record, record.stamp == current else { return .savedUnverified }
        switch record.status {
        case .checking: return .checking
        case .verified: return .verified
        case .rejected: return .rejected
        case .offline: return .offline
        case .unavailable: return .unavailable
        }
    }

    /// The switch has to be on. Saving a key is not enough, and a closed switch cannot verify.
    public static func mayVerify(enabled: Bool, phase: AICredentialPhase) -> Bool {
        guard enabled else { return false }
        switch phase {
        case .savedUnverified, .rejected, .offline, .unavailable: return true
        case .unconfigured, .checking, .verified: return false
        }
    }
}

public struct AIChatMessage: Identifiable, Equatable, Sendable {
    public enum Delivery: Equatable, Sendable {
        case draft
        case sending
        case sent
        case failed
        case cancelled
    }

    public var id: UUID
    public var text: String
    public var delivery: Delivery
    public var records: [VoiceItemDraft]

    public init(id: UUID = UUID(), text: String, delivery: Delivery, records: [VoiceItemDraft] = []) {
        self.id = id
        self.text = text
        self.delivery = delivery
        self.records = records
    }
}

public struct AIChatThread: Equatable, Sendable {
    public var babyID: UUID
    public var messages: [AIChatMessage]

    public init(babyID: UUID, messages: [AIChatMessage] = []) {
        self.babyID = babyID
        self.messages = messages
    }

    public func addingDraft(_ text: String) -> (AIChatThread, UUID) {
        let message = AIChatMessage(text: text, delivery: .draft)
        var copy = self
        copy.messages.append(message)
        return (copy, message.id)
    }

    public func replacingText(_ id: UUID, _ text: String) -> AIChatThread {
        var copy = self
        guard let index = copy.messages.firstIndex(where: { $0.id == id }) else { return copy }
        guard copy.messages[index].delivery == .draft || copy.messages[index].delivery == .failed else { return copy }
        copy.messages[index].text = text
        copy.messages[index].delivery = .draft
        copy.messages[index].records = []
        return copy
    }

    /// Cancel keeps the row and drops any records that were not confirmed.
    public func cancelling(_ id: UUID) -> AIChatThread {
        var copy = self
        guard let index = copy.messages.firstIndex(where: { $0.id == id }) else { return copy }
        copy.messages[index].delivery = .cancelled
        copy.messages[index].records = []
        return copy
    }

    public func finishing(_ id: UUID, records: [VoiceItemDraft]) -> AIChatThread {
        var copy = self
        guard let index = copy.messages.firstIndex(where: { $0.id == id }) else { return copy }
        guard copy.messages[index].delivery == .sending else { return copy }
        copy.messages[index].delivery = .sent
        copy.messages[index].records = records
        return copy
    }
}

public enum AIChatStore {
    public static func thread(_ baby: UUID, in threads: [UUID: AIChatThread]) -> AIChatThread {
        threads[baby] ?? AIChatThread(babyID: baby)
    }
}
