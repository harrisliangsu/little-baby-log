import Foundation
import Testing
@testable import BabyLogKit

struct AIAssistTests {
    @Test func eachKeyStaysOnItsOwnHostAndToolsAreAbsent() throws {
        let token = "secret-token"
        for provider in AIProviderID.allCases {
            let request = AIRequestBuilder.request(provider: provider, userText: "Return json {\"columns\":[]}", token: token)
            #expect(request.url?.host == provider.endpoint.host)
            let body = try #require(request.httpBody)
            let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(object["tools"] == nil)
            #expect(object["model"] as? String == provider.model)
            let raw = String(data: body, encoding: .utf8) ?? ""
            #expect(!raw.contains(token))
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
        }
        let kimi = AIRequestBuilder.request(provider: .kimiAI, userText: "json", token: token)
        #expect(kimi.url?.host == "api.moonshot.ai")
        #expect(AIRequestBuilder.refusesOtherHost(kimi, provider: .deepseek))
    }

    @Test func redactorDropsNamesAndLimitsRows() {
        let names = ["月月"]
        let rows = (0..<12).map { ["月月", "\($0)"] }
        let sample = AIRedactor.mappingSample(headers: ["baby", "n"], rows: rows, babyNames: names)
        #expect(sample.removedNames)
        #expect(!sample.text.contains("月月"))
        #expect(sample.text.contains("Baby"))
        let dataRows = sample.text.components(separatedBy: "\nrows:\n").last?
            .components(separatedBy: "\n").filter { $0.contains("|") } ?? []
        #expect(dataRows.count == 8)
    }

    @Test func badModelOutputIsNotAMapping() throws {
        do {
            _ = try AIProposalDecoder.columns(from: Data("not json".utf8))
            Issue.record("garbage should not decode")
        } catch let error as AIClientError {
            #expect(error == .unreadable)
        } catch {
            Issue.record("unexpected error")
        }
        let mixed = Data(#"{"columns":[{"source":"时间","target":"start"},{"source":"备注","target":"invented"}]}"#.utf8)
        let columns = try? AIProposalDecoder.columns(from: mixed)
        #expect(columns?.first?.target == "start")
        #expect(columns?.last?.target == nil)
        let csv = Data("时间,宝宝,毫升\n2026-03-10T09:00:00Z,Ada,40\n".utf8)
        let table = try #require(StandardImporter.rawTable(data: csv))
        let rebuilt = StandardImporter.schemaCSV(
            headers: table.headers,
            rows: table.rows,
            mappings: [
                ColumnMapping(source: "时间", target: "start"),
                ColumnMapping(source: "宝宝", target: "babyName"),
                ColumnMapping(source: "毫升", target: "amountML"),
                ColumnMapping(source: "备注", target: nil),
            ]
        )
        let file = StandardImporter.parse(data: rebuilt)
        #expect(file.rows.first?.field.babyName == "Ada")
        #expect(file.rows.first?.field.amountML == 40)
        #expect(file.rows.first?.field.start != nil)
    }

    @Test func sendRequiresTheExactApprovedPreview() async throws {
        let transport = ScriptedTransport(payload: Data(#"{"columns":[]}"#.utf8))
        let client = AIClient(transport: transport)
        let preview = AISendPreview(provider: .deepseek, task: .columnMapping, userText: "json columns", removedBabyNames: false)
        let other = AISendPreview(provider: .kimiAI, task: .columnMapping, userText: "json columns", removedBabyNames: false)
        do {
            _ = try await client.send(provider: .deepseek, preview: preview, token: "k", approved: other)
            Issue.record("a different preview must not be sent")
        } catch let error as AIClientError {
            #expect(error == .wrongHost)
        } catch {
            Issue.record("unexpected error")
        }
        #expect(transport.calls == 0)
        let data = try await client.send(provider: .deepseek, preview: preview, token: "k", approved: preview)
        #expect(transport.calls == 1)
        #expect(try AIProposalDecoder.columns(from: data).isEmpty)
    }

    @Test func chatAnswersAndRecordsUseTheSameReply() throws {
        let answer = Data(#"{"choices":[{"message":{"content":"{\"text\":\"今天喂了两次\"}"}}]}"#.utf8)
        #expect(try AIProposalDecoder.chatOutcome(from: answer) == .reply("今天喂了两次"))
        let records = Data(#"{"choices":[{"message":{"content":"{\"items\":[{\"kind\":\"bottle\",\"amountML\":120}]}"}}]}"#.utf8)
        guard case .records(let items) = try AIProposalDecoder.chatOutcome(from: records) else {
            Issue.record("records")
            return
        }
        #expect(items.first?.kind == "bottle")
        #expect(items.first?.amountML == 120.0)
    }
}

private final class ScriptedTransport: AITransport, @unchecked Sendable {
    var calls = 0
    var payload: Data
    init(payload: Data) { self.payload = payload }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        calls += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (payload, response)
    }
}
