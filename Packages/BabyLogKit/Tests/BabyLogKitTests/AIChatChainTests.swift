import CoreData
import Foundation
import Testing
@testable import BabyLogKit

/// Mock transport through the chat parser and into the same fetch the today list and the timeline use.
/// The payload is scripted. This does not call DeepSeek or Kimi.
@MainActor
struct AIChatChainTests {
    private let now = TestSupport.utc(2026, 11, 22, 12)

    @Test func replyComesBackAsTextAndWritesNothing() async throws {
        let store = try makeStore()
        let utterance = "今天喂了几次"
        let response = wrapped(#"{"text":"今天喂了两次"}"#)
        let turn = try await exchange(store: store, utterance: utterance, payloads: [response])
        #expect(turn.requests.count == 1)
        let user = try userContent(turn.requests[0])
        #expect(user.contains("今天喂了几次"))
        #expect(!user.contains("secret-token"))
        #expect(!user.contains("月月"))
        let thread = try #require(turn.thread)
        #expect(thread.messages[0].text == utterance)
        #expect(thread.messages[0].records.isEmpty)
        #expect(thread.messages[1].text == "今天喂了两次")
        #expect(!thread.messages[1].text.contains("Return only the JSON"))
        #expect(events(store.ada).isEmpty)
    }

    @Test func confirmedRecordShowsOnTodayAndTheTimeline() async throws {
        let store = try makeStore()
        let response = wrapped(#"{"items":[{"kind":"bottle","baby":"Current","minutesAgo":5,"amountML":120,"bottle":"formula"}]}"#)
        let turn = try await exchange(store: store, utterance: "奶粉120", payloads: [response])
        let thread = try #require(turn.thread)
        let card = try #require(thread.messages[0].records.first)
        #expect(card.canWrite)
        #expect(events(store.ada).isEmpty)
        #expect(AIChatCommit.save(card, babies: store.babies, in: store.context))
        let saved = events(store.ada)
        #expect(saved.count == 1)
        #expect(saved[0].amountML == 120)
        #expect(saved[0].baby?.displayName == "月月")
        let start = try #require(saved[0].startDate)
        #expect(TimelineRange.today.contains(start, now: now, calendar: TestSupport.utcCalendar))
        let overlapping = try store.context.fetch(LogEvent.requestOverlapping(baby: store.ada, from: TestSupport.utcCalendar.startOfDay(for: now)))
        #expect(overlapping.count == 1)
        #expect(HomeCardMatch.card(for: saved[0]) == .formula)
        #expect(!AIChatCommit.save(card, babies: store.babies, in: store.context))
        #expect(events(store.ada).count == 1)
        let request = try #require(turn.requests.first)
        let object = try #require(JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any])
        #expect(object["model"] as? String == "deepseek-flash")
        #expect(object["tools"] == nil)
        #expect(request.url?.host == "api.deepseek.com")
    }

    @Test func cancelAndAFailedSendLeaveTheLogUntouched() async throws {
        let store = try makeStore()
        let response = wrapped(#"{"items":[{"kind":"diaper","baby":"Current","minutesAgo":1,"diaper":"wet"}]}"#)
        let turn = try await exchange(store: store, utterance: "小便", payloads: [response])
        var thread = try #require(turn.thread)
        let card = try #require(thread.messages[0].records.first)
        #expect(card.canWrite)
        thread = thread.cancelling(thread.messages[0].id)
        #expect(thread.messages[0].records.isEmpty)
        #expect(thread.messages[0].delivery == .cancelled)
        #expect(events(store.ada).isEmpty)

        let transport = StatusTransport(status: 500, payload: Data(#"{"error":"no"}"#.utf8))
        let client = AIClient(transport: transport)
        let outbound = try #require(preview("再试一次"))
        do {
            _ = try await client.send(provider: .deepseek, preview: outbound.preview, token: "secret-token", approved: outbound.preview, model: "deepseek-flash")
            Issue.record("http 500 must not become a card")
        } catch let error as AIClientError {
            #expect(error == .http(500))
        }
        #expect(events(store.ada).isEmpty)
    }

    @Test func retryAfterFailureSavesOnce() async throws {
        let store = try makeStore()
        let response = wrapped(#"{"items":[{"kind":"bottle","baby":"Current","minutesAgo":5,"amountML":90,"bottle":"formula"}]}"#)
        let transport = SequenceTransport(steps: [
            .init(status: 500, payload: Data("{}".utf8)),
            .init(status: 200, payload: response),
        ])
        let client = AIClient(transport: transport)
        let outbound = try #require(preview("奶粉90"))
        do {
            _ = try await client.send(provider: .deepseek, preview: outbound.preview, token: "secret-token", approved: outbound.preview, model: "deepseek-flash")
            Issue.record("first try fails")
        } catch let error as AIClientError {
            #expect(error == .http(500))
        }
        #expect(events(store.ada).isEmpty)
        let data = try await client.send(provider: .deepseek, preview: outbound.preview, token: "secret-token", approved: outbound.preview, model: "deepseek-flash")
        let prepared = sendingThread(store.adaID, text: "奶粉90")
        let thread = try AIChatExchange.apply(
            response: data, to: prepared.thread, message: prepared.id,
            anchor: anchor, map: outbound.map
        )
        let card = try #require(thread.messages[0].records.first)
        #expect(AIChatCommit.save(card, babies: store.babies, in: store.context))
        #expect(!AIChatCommit.save(card, babies: store.babies, in: store.context))
        #expect(events(store.ada).count == 1)
        #expect(events(store.ada)[0].amountML == 90)
    }

    @Test func anotherBabyIsNotWrittenOntoTheCurrentOne() async throws {
        let store = try makeStore()
        let response = wrapped(#"{"items":[{"kind":"bottle","baby":"Baby2","minutesAgo":5,"amountML":80,"bottle":"formula"}]}"#)
        let turn = try await exchange(store: store, utterance: "安安喝了80", payloads: [response])
        var card = try #require(turn.thread?.messages[0].records.first)
        #expect(card.assignedBabyName == "安安")
        #expect(!card.canWrite)
        #expect(!AIChatCommit.save(card, babies: store.babies, in: store.context))
        #expect(events(store.ada).isEmpty)
        #expect(events(store.bo).isEmpty)
        card.confirmBaby("安安")
        #expect(AIChatCommit.save(card, babies: store.babies, in: store.context))
        #expect(events(store.ada).isEmpty)
        #expect(events(store.bo).count == 1)
        #expect(events(store.bo)[0].amountML == 80)
    }

    @Test func closingTheSwitchDropsTheBodyBeforeAnySave() async throws {
        let store = try makeStore()
        let flight = AIFlight()
        let ticket = flight.ticket()
        let transport = SlowChainTransport()
        let client = AIClient(transport: transport)
        let outbound = try #require(preview("奶粉120"))
        let task = Task {
            try await client.send(
                provider: .deepseek, preview: outbound.preview, token: "secret-token", approved: outbound.preview,
                model: "deepseek-flash", access: .ready, flight: flight, ticket: ticket
            )
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        flight.cancelAll()
        do {
            _ = try await task.value
            Issue.record("a late body must not be applied")
        } catch let error as AIClientError {
            #expect(error == .cancelled)
        }
        #expect(events(store.ada).isEmpty)
        #expect(events(store.bo).isEmpty)
    }

    private var anchor: VoiceAnchor {
        VoiceAnchor(startedAt: now, timeZone: TestSupport.utcCalendar.timeZone)
    }

    private func preview(_ utterance: String) -> (preview: AISendPreview, map: VoiceNameMap)? {
        VoiceDrafts.outbound(
            transcript: utterance, anchor: anchor, currentBaby: "月月", otherBabies: ["安安"], provider: .deepseek
        )
    }

    private func exchange(store: Store, utterance: String, payloads: [Data]) async throws -> (requests: [URLRequest], thread: AIChatThread?) {
        let outbound = try #require(preview(utterance))
        let transport = SequenceTransport(steps: payloads.map { .init(status: 200, payload: $0) })
        let client = AIClient(transport: transport)
        let data = try await client.send(
            provider: .deepseek, preview: outbound.preview, token: "secret-token", approved: outbound.preview, model: "deepseek-flash"
        )
        let prepared = sendingThread(store.adaID, text: utterance)
        let thread = try AIChatExchange.apply(
            response: data, to: prepared.thread, message: prepared.id,
            anchor: anchor, map: outbound.map
        )
        return (transport.requests, thread)
    }

    private func sendingThread(_ baby: UUID, text: String) -> (thread: AIChatThread, id: UUID) {
        var thread = AIChatThread(babyID: baby)
        let added = thread.addingDraft(text)
        thread = added.0
        let index = thread.messages.firstIndex(where: { $0.id == added.1 })!
        thread.messages[index].delivery = .sending
        return (thread, added.1)
    }

    private func events(_ baby: Baby) -> [LogEvent] {
        (try? baby.managedObjectContext?.fetch(LogEvent.requestAll(baby: baby, ascending: true))) ?? []
    }

    private func userContent(_ request: URLRequest) throws -> String {
        let object = try #require(JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any])
        let messages = try #require(object["messages"] as? [[String: Any]])
        return messages.compactMap { $0["content"] as? String }.joined(separator: "\n")
    }

    private func makeStore() throws -> Store {
        let (_, context) = TestSupport.makeContext()
        let ada = Baby.create(name: "月月", birthDate: now, in: context)
        let bo = Baby.create(name: "安安", birthDate: now, in: context)
        #expect(context.saveIfNeeded())
        return Store(context: context, ada: ada, bo: bo)
    }

    private func wrapped(_ json: String) -> Data {
        let body: [String: Any] = ["choices": [["message": ["content": json]]]]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }
}

private struct Store {
    var context: NSManagedObjectContext
    var ada: Baby
    var bo: Baby
    var babies: [Baby] { [ada, bo] }
    var adaID: UUID { ada.uuid ?? UUID() }
}

private struct TransportStep {
    var status: Int
    var payload: Data
}

private final class SequenceTransport: AITransport, @unchecked Sendable {
    var requests: [URLRequest] = []
    var steps: [TransportStep]
    init(steps: [TransportStep]) { self.steps = steps }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let step = steps.isEmpty ? TransportStep(status: 500, payload: Data()) : steps.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: step.status, httpVersion: nil, headerFields: nil)!
        return (step.payload, response)
    }
}

private final class StatusTransport: AITransport, @unchecked Sendable {
    var status: Int
    var payload: Data
    init(status: Int, payload: Data) { self.status = status; self.payload = payload }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (payload, response)
    }
}

private final class SlowChainTransport: AITransport, @unchecked Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(nanoseconds: 200_000_000)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let json = #"{"choices":[{"message":{"content":"{\"items\":[{\"kind\":\"bottle\",\"amountML\":120,\"bottle\":\"formula\",\"minutesAgo\":1}]}"}}]}"#
        return (Data(json.utf8), response)
    }
}
