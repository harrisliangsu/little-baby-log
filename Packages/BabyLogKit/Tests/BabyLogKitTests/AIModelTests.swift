import Foundation
import Testing
@testable import BabyLogKit

struct AIModelTests {
    @Test func defaultsMatchTheOfficialIDs() {
        #expect(AIModelCatalog.defaultID(for: .deepseek) == "deepseek-flash")
        #expect(AIProviderID.deepseek.model == "deepseek-flash")
        #expect(AIModelCatalog.defaultID(for: .kimiAI) == "kimi-k3.1-pro")
        #expect(AIModelCatalog.defaultID(for: .kimiCN) == "kimi-k3.1-pro")
        #expect(AIModelCatalog.choices(for: .kimiAI).map(\.rawID) == AIModelCatalog.choices(for: .kimiCN).map(\.rawID))
        let banned = ["deepseek-chat", "deepseek-reasoner", "deepseek-v4-flash", "kimi-k2.7-code", "kimi-k2.6"]
        for provider in AIProviderID.allCases {
            let ids = AIModelCatalog.choices(for: provider).map(\.rawID)
            for name in banned {
                #expect(!ids.contains(name))
            }
        }
    }

    @Test func unknownAndForeignIDsFallBackAndStayOnTheirProvider() throws {
        var selection = AIModelSelection()
        #expect(selection.current(for: .deepseek) == "deepseek-flash")
        #expect(selection.current(for: .kimiAI) == "kimi-k3.1-pro")

        selection = selection.choosing("deepseek-v4-pro", for: .deepseek)
        selection = selection.choosing("kimi-k3", for: .kimiCN)
        #expect(selection.current(for: .deepseek) == "deepseek-v4-pro")
        #expect(selection.current(for: .kimiCN) == "kimi-k3")
        #expect(selection.current(for: .kimiAI) == "kimi-k3.1-pro")
        let restored = AIModelSelection(json: selection.json)
        #expect(restored.current(for: .kimiCN) == "kimi-k3")
        #expect(restored.current(for: .deepseek) == "deepseek-v4-pro")

        selection = selection.choosing("kimi-k3", for: .deepseek)
        selection = selection.choosing("not-a-model", for: .kimiAI)
        #expect(selection.current(for: .deepseek) == "deepseek-flash")
        #expect(selection.current(for: .kimiAI) == "kimi-k3.1-pro")
        #expect(selection.current(for: .kimiCN) == "kimi-k3")

        let deepseek = try body(provider: .deepseek, model: selection.current(for: .deepseek))
        #expect(deepseek.model == "deepseek-flash")
        #expect(deepseek.thinking == "disabled")
        #expect(deepseek.maxTokens == 800)
        #expect(deepseek.tools == nil)
        let kimi = try body(provider: .kimiAI, model: "kimi-k3.1-pro-highspeed")
        #expect(kimi.model == "kimi-k3.1-pro-highspeed")
        #expect(kimi.tools == nil)
        #expect(kimi.format == "json_object")
        let rejected = try body(provider: .kimiCN, model: "deepseek-v4-pro")
        #expect(rejected.model == "kimi-k3.1-pro")
    }

    private func body(provider: AIProviderID, model: String) throws -> (model: String, thinking: String?, maxTokens: Int?, tools: Any?, format: String?) {
        let request = AIRequestBuilder.request(provider: provider, model: model, userText: "json", token: "secret-token")
        let data = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let raw = String(decoding: data, as: UTF8.self)
        #expect(!raw.contains("secret-token"))
        let format = (object["response_format"] as? [String: Any])?["type"] as? String
        let thinking = (object["thinking"] as? [String: Any])?["type"] as? String
        let tokens = (object["max_tokens"] as? NSNumber)?.intValue
        return (
            object["model"] as? String ?? "",
            thinking,
            tokens,
            object["tools"],
            format
        )
    }
}
