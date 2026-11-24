import Testing
import Foundation
@testable import BabyLogKit

struct DeviceRepairTests {
    @Test func iconBoxFitsInsideTheCircle() {
        let side: CGFloat = 44 * 0.56
        let placement = IconPlacement.fitting(into: side, height: side)
        #expect(placement.scale < 1)
        #expect(placement.scale == side / 256)
        #expect(placement.viewBoxFits(width: side, height: side))
        let far = placement.point(256, 256)
        #expect(far.x <= side + 0.01)
        #expect(far.y <= side + 0.01)
        // The old draw used the path's own 256-point coordinates in a ~25 point frame.
        #expect(256 > side)
    }

    @Test func appearanceAndStyleStayIndependent() {
        let defaults = UserDefaults(suiteName: "chrome-\(UUID().uuidString)")!
        var chrome = ChromeSelection(mode: .system, style: .classic)
        chrome = chrome.choosingMode(.light)
        #expect(chrome.mode == .light)
        #expect(chrome.style == .classic)
        chrome = chrome.choosingStyle(.liquidGlass)
        #expect(chrome.mode == .light)
        #expect(chrome.style == .liquidGlass)
        chrome = chrome.choosingMode(.dark)
        #expect(chrome.style == .liquidGlass)
        chrome.save(to: defaults)
        let loaded = ChromeSelection.load(from: defaults)
        #expect(loaded == ChromeSelection(mode: .dark, style: .liquidGlass))
    }

    @Test func homeCardsMoveWithoutCopyingOrDeleting() {
        var layout = BabyHomeLayout(cards: HomeCard.defaultOrder)
        layout = layout.setting(.formula, visible: false)
        #expect(!layout.recordCards.contains(.formula))
        #expect(layout.otherCards.contains(.formula))
        #expect(Set(layout.recordCards).isDisjoint(with: Set(layout.otherCards)))
        let stored = HomeLayoutStore.save(layout, babyID: UUID(uuidString: "00000000-0000-0000-0000-0000000000aa")!, into: nil)
        let other = UUID(uuidString: "00000000-0000-0000-0000-0000000000bb")!
        let untouched = HomeLayoutStore.load(babyID: other, from: stored)
        #expect(untouched.recordCards.contains(.formula))
        let again = HomeLayoutStore.load(babyID: UUID(uuidString: "00000000-0000-0000-0000-0000000000aa")!, from: stored)
        #expect(again.recordCards == layout.recordCards)
    }

    @Test func greetingPromptAsksForJSONAndAPlainReplyIsShown() throws {
        let outbound = try #require(VoiceDrafts.outbound(
            transcript: "你好啊",
            anchor: VoiceAnchor(startedAt: Date(timeIntervalSince1970: 1_700_000_000), timeZone: .current),
            currentBaby: "月月",
            otherBabies: [],
            provider: .deepseek
        ))
        #expect(outbound.preview.userText.lowercased().contains("json"))
        #expect(outbound.preview.userText.contains("\"text\""))
        let prose = Data(#"{"choices":[{"message":{"content":"你好"}}]}"#.utf8)
        #expect(try AIProposalDecoder.chatOutcome(from: prose) == .reply("你好"))
        let object = Data(#"{"choices":[{"message":{"content":"{\"text\":\"你好啊\"}"}}]}"#.utf8)
        #expect(try AIProposalDecoder.chatOutcome(from: object) == .reply("你好啊"))
        let sse = Data("""
        data: {"choices":[{"delta":{"content":"你好啊"}}]}

        data: [DONE]

        """.utf8)
        #expect(try AIProposalDecoder.chatOutcome(from: sse) == .reply("你好啊"))
    }

    @Test func failedChatNamesTheReason() {
        #expect(AIChatFailure.from(AIClientError.http(400)) == .rejectedRequest)
        #expect(AIChatFailure.from(AIClientError.http(401)) == .unauthorized)
        #expect(AIChatFailure.from(AIClientError.unreadable) == .unread)
        #expect(AIChatFailure.from(AIClientError.noActiveProvider) == .noProvider)
        #expect(AIChatFailure.from(access: .offline) == .offline)
        #expect(AIChatFailure.from(access: .missingCredential) == .noProvider)
        let text = AIChatFailure.rejectedRequest.text(chinese: true)
        #expect(text.contains("重试"))
        #expect(!text.contains("sk-"))
        #expect(text != "重试")
    }
}
