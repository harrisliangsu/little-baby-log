import Foundation
import Testing
@testable import BabyLogKit

struct VoiceGateTests {
    @Test func closedMissingAndOfflineNeverReachTheNetworkOrTheMicrophone() async throws {
        for access in [AIAccess.off, .missingCredential, .offline] {
            #expect(!access.mayRequestMicrophone)
            #expect(!access.maySend)
            #expect(access.opensAssistantSettings)
            let transport = ScriptedVoiceTransport(payload: Data(#"{"items":[]}"#.utf8))
            let client = AIClient(transport: transport)
            let preview = AISendPreview(provider: .deepseek, task: .recordDraft, userText: "json", removedBabyNames: false)
            do {
                _ = try await client.send(
                    provider: .deepseek, preview: preview, token: "secret", approved: preview,
                    access: access, flight: AIFlight(), ticket: 0
                )
                Issue.record("closed assistant must not send")
            } catch let error as AIClientError {
                #expect(error == .cancelled)
            }
            #expect(transport.calls == 0)
        }
        let rejected = AIAccess.evaluate(enabled: true, hasCredential: true, credentialRejected: true, isOnline: true)
        #expect(rejected == .missingCredential)
        #expect(!rejected.mayRequestMicrophone)
    }

    @Test func turningTheSwitchOffDropsAnInFlightResult() async {
        let flight = AIFlight()
        let ticket = flight.ticket()
        let transport = SlowVoiceTransport()
        let client = AIClient(transport: transport)
        let preview = AISendPreview(provider: .deepseek, task: .recordDraft, userText: "json", removedBabyNames: false)
        let task = Task {
            try await client.send(
                provider: .deepseek, preview: preview, token: "secret", approved: preview,
                access: .ready, flight: flight, ticket: ticket
            )
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        flight.cancelAll()
        do {
            _ = try await task.value
            Issue.record("a late result must not come back")
        } catch let error as AIClientError {
            #expect(error == .cancelled)
        } catch {
            Issue.record("unexpected error")
        }
        #expect(!flight.isCurrent(ticket))
        let next = flight.ticket()
        #expect(flight.isCurrent(next))
    }

    @Test func cancelWritesNothingAndFailureReturnsToManual() {
        #expect(VoiceNextStep.after(stopped: false, transcript: "喝了120", failed: false) == .discard)
        #expect(VoiceNextStep.after(stopped: true, transcript: "  ", failed: false) == .manual)
        #expect(VoiceNextStep.after(stopped: true, transcript: nil, failed: true) == .manual)
        #expect(VoiceNextStep.after(stopped: true, transcript: "奶粉120", failed: false) == .preview)
        #expect(VoiceDrafts.outbound(
            transcript: "  ", anchor: VoiceAnchor(startedAt: .now, timeZone: .current),
            currentBaby: "月月", otherBabies: [], provider: .deepseek
        ) == nil)
    }

    @Test func relativeTimeUsesTheRecordingAnchorAcrossMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let started = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 0, minute: 8)))
        let anchor = VoiceAnchor(startedAt: started, timeZone: calendar.timeZone)
        let item = VoiceModelItem(
            kind: "bottle", baby: "Current", minutesAgo: 20,
            start: "2020-01-01T00:00:00Z", amountML: 90, bottle: "formula"
        )
        let map = VoiceNameMap(currentName: "月月", tokenToName: ["Current": "月月"], mentionedTokens: ["Current"])
        let draft = try #require(VoiceDrafts.resolve(items: [item], anchor: anchor, map: map).first)
        let expected = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 23, minute: 48)))
        #expect(draft.start == expected)
        #expect(draft.canWrite)
        #expect(draft.assignedBabyName == "月月")
        #expect(!draft.conflictsWithCurrentBaby)
        #expect(draft.eventDraft()?.amountML == 90)
        #expect(draft.eventDraft()?.bottleContent.rawValue == BottleContent.formula.rawValue)
    }

    @Test func anotherBabyIsNeverSilentlyWrittenToTheCurrentOne() {
        let map = VoiceNameMap(
            currentName: "月月",
            tokenToName: ["Current": "月月", "Baby2": "安安"],
            mentionedTokens: ["Baby2"]
        )
        let anchor = VoiceAnchor(startedAt: Date(timeIntervalSince1970: 1_700_000_000), timeZone: .gmt)
        let item = VoiceModelItem(kind: "bottle", baby: "Current", minutesAgo: 5, amountML: 80, bottle: "formula")
        var draft = VoiceDrafts.resolve(items: [item], anchor: anchor, map: map)[0]
        #expect(draft.conflictsWithCurrentBaby)
        #expect(draft.assignedBabyName == "安安")
        #expect(!draft.canWrite)
        #expect(draft.eventDraft() == nil)
        #expect(draft.confirmed() == nil)
        draft.confirmBaby("安安")
        #expect(!draft.conflictsWithCurrentBaby)
        #expect(draft.canWrite)
        #expect(draft.assignedBabyName == "安安")
    }

    @Test func bothNamesWithoutAChoiceStayUnsaved() {
        let map = VoiceNameMap(
            currentName: "月月",
            tokenToName: ["Current": "月月", "Baby2": "安安"],
            mentionedTokens: ["Current", "Baby2"]
        )
        let anchor = VoiceAnchor(startedAt: Date(timeIntervalSince1970: 1_700_000_000), timeZone: .gmt)
        let missing = VoiceModelItem(kind: "diaper", minutesAgo: 1, diaper: "wet")
        let draft = VoiceDrafts.resolve(items: [missing], anchor: anchor, map: map)[0]
        #expect(draft.uncertain.contains(.baby))
        #expect(!draft.canWrite)
        #expect(draft.confirmed() == nil)
        let chosen = VoiceModelItem(kind: "diaper", baby: "Current", minutesAgo: 1, diaper: "wet")
        let current = VoiceDrafts.resolve(items: [chosen], anchor: anchor, map: map)[0]
        #expect(!current.conflictsWithCurrentBaby)
        #expect(current.assignedBabyName == "月月")
        #expect(current.canWrite)
    }

    @Test func uncertainAmountIsMarkedUntilThePersonConfirmsIt() {
        let map = VoiceNameMap(currentName: "月月", tokenToName: ["Current": "月月"], mentionedTokens: [])
        let anchor = VoiceAnchor(startedAt: Date(timeIntervalSince1970: 1_700_000_000), timeZone: .gmt)
        let item = VoiceModelItem(kind: "bottle", baby: "Current", minutesAgo: 1, amountML: 100, bottle: "formula", uncertain: ["amount"])
        let draft = VoiceDrafts.resolve(items: [item], anchor: anchor, map: map)[0]
        #expect(draft.uncertain.contains(.amount))
        #expect(!draft.canWrite)
        #expect(draft.confirmed()?.canWrite == true)
        #expect(draft.confirmed()?.amountML == 100)
    }

    @Test func outboundTextHasNoAudioAndNoBabyNames() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let started = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 0, minute: 8)))
        let anchor = VoiceAnchor(startedAt: started, timeZone: calendar.timeZone)
        let outbound = try #require(VoiceDrafts.outbound(
            transcript: "安安喝了120，月月换了尿布",
            anchor: anchor,
            currentBaby: "月月",
            otherBabies: ["安安"],
            provider: .kimiCN
        ))
        let request = AIRequestBuilder.request(provider: .kimiCN, userText: outbound.preview.userText, token: "secret-token")
        let body = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["audio"] == nil)
        #expect(object["file"] == nil)
        let raw = String(decoding: body, as: UTF8.self)
        #expect(!raw.contains("月月"))
        #expect(!raw.contains("安安"))
        #expect(!raw.contains("secret-token"))
        #expect(raw.contains(anchor.iso8601))
        #expect(raw.contains("Asia/Shanghai"))
        #expect(outbound.preview.removedBabyNames)
        #expect(outbound.map.tokenToName["Baby2"] == "安安")
    }

    @Test func longerBabyNameIsReplacedFirst() {
        let redacted = VoiceDrafts.redact(transcript: "安安喝了120", currentBaby: "安", otherBabies: ["安安"])
        #expect(redacted.text.contains("Baby2"))
        #expect(!redacted.text.contains("安"))
        #expect(redacted.map.mentionedTokens == ["Baby2"])
    }

    @Test func summaryUsesOnlyTheFactsThatWerePassed() {
        let text = HistorySummaryText.userText(total: "2次", facts: [SummaryFact(id: "abc", line: "08:00 120ml")])
        #expect(text.contains("abc"))
        #expect(text.contains("08:00 120ml"))
        #expect(text.contains("2次"))
        #expect(text.contains("不要写百分位"))
        #expect(text.contains("不要下健康结论"))
        #expect(!text.contains("99"))
        #expect(!text.contains("WHO"))
    }

    @Test func chatWrapperStillDecodesTheJSONObject() throws {
        let inner = #"{"items":[{"kind":"diaper","minutesAgo":10,"diaper":"wet"}]}"#
        let wrapper: [String: Any] = ["choices": [["message": ["content": inner]]]]
        let data = try JSONSerialization.data(withJSONObject: wrapper)
        let items = try VoiceDrafts.items(from: data)
        #expect(items.first?.kind == "diaper")
        #expect(items.first?.minutesAgo == 10)
        let columns = try AIProposalDecoder.columns(from: Data(#"{"choices":[{"message":{"content":"{\"columns\":[{\"source\":\"时间\",\"target\":\"start\"}]}"}}]}"#.utf8))
        #expect(columns.first?.target == "start")
    }
}

private final class ScriptedVoiceTransport: AITransport, @unchecked Sendable {
    var calls = 0
    var payload: Data
    init(payload: Data) { self.payload = payload }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        calls += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (payload, response)
    }
}

private final class SlowVoiceTransport: AITransport, @unchecked Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(nanoseconds: 200_000_000)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(#"{"items":[]}"#.utf8), response)
    }
}
