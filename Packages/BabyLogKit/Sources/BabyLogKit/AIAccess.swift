import Foundation

/// Every AI feature asks this before a microphone prompt or a network call.
/// Closed is the default. Opening the switch does not send anything by itself.
public enum AIAccess: Equatable, Sendable {
    case off
    case missingCredential
    case offline
    case ready

    public static func evaluate(enabled: Bool, hasCredential: Bool, credentialRejected: Bool, isOnline: Bool) -> AIAccess {
        if !enabled { return .off }
        if !hasCredential || credentialRejected { return .missingCredential }
        if !isOnline { return .offline }
        return .ready
    }

    public var mayRequestMicrophone: Bool { self == .ready }
    public var maySend: Bool { self == .ready }
    public var opensAssistantSettings: Bool { self != .ready }
}

/// A generation counter. Turning the assistant off bumps it, so a reply that arrives later is not current.
public final class AIFlight: @unchecked Sendable {
    public static let shared = AIFlight()

    private let lock = NSLock()
    private var generation = 0

    public init() {}

    public func ticket() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    public func cancelAll() {
        lock.lock()
        generation &+= 1
        lock.unlock()
    }

    public func isCurrent(_ ticket: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return ticket == generation
    }
}

public enum AISendGuard {
    public static func shouldSend(access: AIAccess, flight: AIFlight?, ticket: Int) -> Bool {
        guard access.maySend else { return false }
        guard let flight else { return true }
        return flight.isCurrent(ticket)
    }
}
