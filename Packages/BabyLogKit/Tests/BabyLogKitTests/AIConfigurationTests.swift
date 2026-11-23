import Foundation
import Testing
@testable import BabyLogKit

struct AIConfigurationTests {
    @Test func legacyKeysStaySeparateAndUnselectedKimiIsNotActivated() {
        let result = AIConfigurationMigration.migrate(
            storedProvider: nil,
            modelJSON: "",
            keys: ["deepseek": "sk-deep", "kimiCN": "sk-kimi"]
        )
        #expect(result.catalog.items.count == 2)
        #expect(result.catalog.active?.provider == .deepseek)
        #expect(result.moves.map(\.fromAccount).sorted() == ["deepseek", "kimiCN"])
        #expect(result.moves.allSatisfy { $0.fromAccount != $0.toAccount })
        let deleted = result.catalog.deleting(AIConfigurationMigration.legacyDeepSeek)
        #expect(deleted.activeID == nil)
        #expect(deleted.items.map(\.provider) == [.kimiCN])
    }

    @Test func explicitProviderWinsAndDeletingItDoesNotPickAnother() {
        let result = AIConfigurationMigration.migrate(
            storedProvider: "kimiAI",
            modelJSON: #"{"kimiAI":"kimi-k3"}"#,
            keys: ["deepseek": "sk-deep", "kimiAI": "sk-ai"]
        )
        #expect(result.catalog.active?.provider == .kimiAI)
        #expect(result.catalog.active?.model == "kimi-k3")
        let cleared = result.catalog.deleting(result.catalog.activeID!)
        #expect(cleared.active == nil)
        #expect(cleared.items.contains { $0.provider == .deepseek })
    }

    @Test func savedKeyWithoutACheckIsNotVerifiedAcrossConfigurations() {
        let stamp = AIVerifyStamp(provider: "deepseek", model: "deepseek-flash", lastFour: "abcd", configurationID: "one", endpointHost: "api.deepseek.com")
        let verified = AIVerifyRecord(stamp: stamp, status: .verified)
        let other = AIVerifyStamp(provider: "deepseek", model: "deepseek-flash", lastFour: "abcd", configurationID: "two", endpointHost: "api.deepseek.com")
        #expect(AICredentialState.phase(hasKey: true, current: other, record: verified) == .savedUnverified)
        #expect(AICredentialState.phase(hasKey: true, current: stamp, record: nil) == .savedUnverified)
    }
}
