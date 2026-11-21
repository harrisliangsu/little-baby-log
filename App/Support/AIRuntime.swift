import Foundation
import BabyLogKit

extension AIPreferences {
    static let rejectedKey = "aiAssistCredentialRejected"
}

/// One place that decides whether any assistant feature may talk to the network.
enum AIRuntime {
    static func access() -> AIAccess {
        let token = AIKeyStore.token(provider: AIPreferences.provider)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AIAccess.evaluate(
            enabled: AIPreferences.isEnabled,
            hasCredential: token?.isEmpty == false,
            credentialRejected: UserDefaults.standard.bool(forKey: AIPreferences.rejectedKey),
            isOnline: NetworkGate.shared.isOnline
        )
    }

    static func send(preview: AISendPreview, ticket: Int) async throws -> Data {
        let access = access()
        guard access.maySend, let token = AIKeyStore.token(provider: preview.provider) else {
            throw AIClientError.cancelled
        }
        do {
            return try await AIClient(transport: LockedHostTransport()).send(
                provider: preview.provider,
                preview: preview,
                token: token,
                approved: preview,
                access: access,
                flight: AIFlight.shared,
                ticket: ticket
            )
        } catch let error as AIClientError {
            if case .http(let code) = error, code == 401 || code == 403 {
                UserDefaults.standard.set(true, forKey: AIPreferences.rejectedKey)
                AIFlight.shared.cancelAll()
            }
            throw error
        }
    }
}

/// In-flight assistant work. Closing the switch cancels these tasks and invalidates their tickets.
final class AITasks: @unchecked Sendable {
    static let shared = AITasks()

    private let lock = NSLock()
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func run(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        let task = Task { @MainActor in
            await operation()
            self.finish(id)
        }
        lock.lock()
        tasks[id] = task
        lock.unlock()
    }

    func cancelAll() {
        AIFlight.shared.cancelAll()
        lock.lock()
        let running = Array(tasks.values)
        tasks.removeAll()
        lock.unlock()
        running.forEach { $0.cancel() }
    }

    private func finish(_ id: UUID) {
        lock.lock()
        tasks[id] = nil
        lock.unlock()
    }
}
