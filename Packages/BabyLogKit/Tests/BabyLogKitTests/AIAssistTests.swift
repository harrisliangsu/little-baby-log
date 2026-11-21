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
        #expect(sample.text.components(separatedBy: "\n").filter { $0.contains("|") }.count == 8)
    }

    @Test func badModelOutputIsNotAMapping() {
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
