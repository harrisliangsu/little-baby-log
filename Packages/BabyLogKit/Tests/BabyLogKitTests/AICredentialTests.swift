import Foundation
import Testing
@testable import BabyLogKit

struct AICredentialTests {
    private let deepseek = AIVerifyStamp(provider: "deepseek", model: "deepseek-flash", lastFour: "1234")

    @Test func savingAKeyIsNotVerification() {
        #expect(AICredentialState.phase(hasKey: true, current: deepseek, record: nil) == .savedUnverified)
        #expect(AICredentialState.phase(hasKey: false, current: deepseek, record: nil) == .unconfigured)
        let verified = AIVerifyRecord(stamp: deepseek, status: .verified)
        #expect(AICredentialState.phase(hasKey: true, current: deepseek, record: verified) == .verified)
    }

    @Test func anotherProviderModelOrKeyDoesNotInheritSuccess() {
        let verified = AIVerifyRecord(stamp: deepseek, status: .verified)
        let otherProvider = AIVerifyStamp(provider: "kimiCN", model: "kimi-k3.1-pro", lastFour: "1234")
        let otherModel = AIVerifyStamp(provider: "deepseek", model: "deepseek-v4-pro", lastFour: "1234")
        let otherKey = AIVerifyStamp(provider: "deepseek", model: "deepseek-flash", lastFour: "9999")
        #expect(AICredentialState.phase(hasKey: true, current: otherProvider, record: verified) == .savedUnverified)
        #expect(AICredentialState.phase(hasKey: true, current: otherModel, record: verified) == .savedUnverified)
        #expect(AICredentialState.phase(hasKey: true, current: otherKey, record: verified) == .savedUnverified)
    }

    @Test func closedSwitchCannotVerifyAndNetworkIsNotABadKey() {
        #expect(!AICredentialState.mayVerify(enabled: false, phase: .savedUnverified))
        #expect(AICredentialState.mayVerify(enabled: true, phase: .savedUnverified))
        #expect(!AICredentialState.mayVerify(enabled: true, phase: .unconfigured))
        #expect(!AICredentialState.mayVerify(enabled: true, phase: .checking))
        let offline = AIVerifyRecord(stamp: deepseek, status: .offline)
        #expect(AICredentialState.phase(hasKey: true, current: deepseek, record: offline) == .offline)
        let rejected = AIVerifyRecord(stamp: deepseek, status: .rejected)
        #expect(AICredentialState.phase(hasKey: true, current: deepseek, record: rejected) == .rejected)
        #expect(AICredentialState.phase(hasKey: true, current: deepseek, record: offline) != .rejected)
    }

    @Test func probeNamesTheModelAndCarriesNoBabyText() throws {
        let request = AIRequestBuilder.request(
            provider: .deepseek,
            model: "deepseek-v4-pro",
            userText: AIProbe.userText,
            token: "secret-token"
        )
        let data = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(object["messages"] as? [[String: Any]])
        let user = messages.compactMap { $0["content"] as? String }.joined(separator: "\n")
        let raw = String(decoding: data, as: UTF8.self)
        #expect(object["model"] as? String == "deepseek-v4-pro")
        #expect(object["tools"] == nil)
        #expect(user.contains(AIProbe.userText))
        #expect(!user.contains("secret-token"))
        #expect(!user.contains("月月"))
        #expect(!raw.contains("secret-token"))
        #expect(request.url?.host == "api.deepseek.com")
    }

    @Test func chatDraftsStayOnTheirBabyUntilConfirmed() {
        let ada = UUID()
        let bo = UUID()
        var threads: [UUID: AIChatThread] = [:]
        var adaThread = AIChatStore.thread(ada, in: threads)
        let (withDraft, id) = adaThread.addingDraft("喝了120")
        adaThread = withDraft
        threads[ada] = adaThread
        #expect(AIChatStore.thread(bo, in: threads).messages.isEmpty)
        #expect(adaThread.messages.first?.delivery == .draft)
        #expect(adaThread.messages.first?.records.isEmpty == true)
        adaThread = adaThread.cancelling(id)
        #expect(adaThread.messages.first?.delivery == .cancelled)
        #expect(adaThread.messages.first?.records.isEmpty == true)
        threads[ada] = adaThread
        #expect(AIChatStore.thread(ada, in: threads).messages.count == 1)
        #expect(AIChatStore.thread(bo, in: threads).messages.isEmpty)
    }
}
