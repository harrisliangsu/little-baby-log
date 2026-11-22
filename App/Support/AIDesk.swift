import Foundation
import BabyLogKit

struct AIPendingSend: Equatable {
    var baby: UUID
    var message: UUID
}

/// Settings and the chat read this one object. Keys stay in the keychain.
@MainActor
final class AIDesk: ObservableObject {
    static weak var current: AIDesk?

    @Published private(set) var threads: [UUID: AIChatThread] = [:]
    @Published private(set) var verification: AIVerifyRecord?
    @Published var pendingSend: AIPendingSend?

    func thread(for baby: UUID) -> AIChatThread {
        AIChatStore.thread(baby, in: threads)
    }

    @discardableResult
    func addDraft(baby: UUID, text: String) -> UUID {
        var thread = thread(for: baby)
        let (next, id) = thread.addingDraft(text)
        threads[baby] = next
        return id
    }

    func setText(baby: UUID, id: UUID, text: String) {
        var thread = thread(for: baby)
        guard let index = thread.messages.firstIndex(where: { $0.id == id }) else { return }
        thread.messages[index].text = text
        threads[baby] = thread
    }

    func replaceText(baby: UUID, id: UUID, text: String) {
        threads[baby] = thread(for: baby).replacingText(id, text)
    }

    func cancel(baby: UUID, id: UUID) {
        threads[baby] = thread(for: baby).cancelling(id)
    }

    func finish(baby: UUID, id: UUID, records: [VoiceItemDraft]) {
        threads[baby] = thread(for: baby).finishing(id, records: records)
    }

    func replaceThread(_ thread: AIChatThread) {
        threads[thread.babyID] = thread
    }

    @discardableResult
    func seed(baby: UUID, key: String, text: String) -> UUID? {
        let token = baby.uuidString + "|" + key
        guard seeded.insert(token).inserted else { return nil }
        guard !text.isEmpty else { return nil }
        return addDraft(baby: baby, text: text)
    }

    func notePending(baby: UUID, message: UUID) {
        pendingSend = AIPendingSend(baby: baby, message: message)
    }

    func appendReply(baby: UUID, text: String) {
        var thread = thread(for: baby)
        thread.messages.append(AIChatMessage(text: text, delivery: .sent))
        threads[baby] = thread
    }

    @Published private var seeded: Set<String> = []

    func setDelivery(baby: UUID, id: UUID, delivery: AIChatMessage.Delivery) {
        var thread = thread(for: baby)
        guard let index = thread.messages.firstIndex(where: { $0.id == id }) else { return }
        thread.messages[index].delivery = delivery
        if delivery != .sent { thread.messages[index].records = [] }
        threads[baby] = thread
    }

    func stamp(for provider: AIProviderID) -> AIVerifyStamp {
        AIVerifyStamp(
            provider: provider.rawValue,
            model: AIPreferences.modelID(for: provider),
            lastFour: AIKeyStore.lastFour(provider: provider)
        )
    }

    func phase(for provider: AIProviderID) -> AICredentialPhase {
        let token = AIKeyStore.token(provider: provider)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return AICredentialState.phase(
            hasKey: token?.isEmpty == false,
            current: stamp(for: provider),
            record: verification
        )
    }

    func isRejected(_ provider: AIProviderID) -> Bool {
        phase(for: provider) == .rejected
    }

    func noteSaved(_ provider: AIProviderID) {
        if verification?.stamp.provider == provider.rawValue {
            verification = nil
        }
    }

    func markRejected(_ provider: AIProviderID) {
        let stamp = stamp(for: provider)
        guard !stamp.lastFour.isEmpty else { return }
        verification = AIVerifyRecord(stamp: stamp, status: .rejected)
    }

    func noteDeleted(_ provider: AIProviderID) {
        if verification?.stamp.provider == provider.rawValue {
            verification = nil
        }
        AITasks.shared.cancelAll()
    }

    func verify(_ provider: AIProviderID) async {
        let current = phase(for: provider)
        guard AICredentialState.mayVerify(enabled: AIPreferences.isEnabled, phase: current) else { return }
        let stamp = stamp(for: provider)
        verification = AIVerifyRecord(stamp: stamp, status: .checking)
        let preview = AISendPreview(
            provider: provider,
            task: .connectionTest,
            userText: AIProbe.userText,
            removedBabyNames: false
        )
        let ticket = AIFlight.shared.ticket()
        do {
            _ = try await AIRuntime.send(preview: preview, ticket: ticket)
            guard AIPreferences.isEnabled, AIFlight.shared.isCurrent(ticket), self.stamp(for: provider) == stamp else {
                if verification?.stamp == stamp, verification?.status == .checking { verification = nil }
                return
            }
            verification = AIVerifyRecord(stamp: stamp, status: .verified)
        } catch AIClientError.cancelled {
            if verification?.stamp == stamp, verification?.status == .checking { verification = nil }
        } catch is CancellationError {
            if verification?.stamp == stamp, verification?.status == .checking { verification = nil }
        } catch let error as AIClientError {
            let status: AIVerifyStatus
            if case .http(let code) = error, code == 401 || code == 403 {
                status = .rejected
            } else {
                status = .unavailable
            }
            guard self.stamp(for: provider) == stamp else { return }
            verification = AIVerifyRecord(stamp: stamp, status: status)
        } catch is URLError {
            guard self.stamp(for: provider) == stamp else { return }
            verification = AIVerifyRecord(stamp: stamp, status: .offline)
        } catch {
            guard self.stamp(for: provider) == stamp else { return }
            verification = AIVerifyRecord(stamp: stamp, status: .unavailable)
        }
    }
}
