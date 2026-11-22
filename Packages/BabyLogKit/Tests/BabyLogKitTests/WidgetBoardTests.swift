import Foundation
import Testing
@testable import BabyLogKit

struct WidgetBoardTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func sizesKeepOrderAndSayWhatDoesNotFit() {
        let cards: [HomeCard] = [.formula, .wet, .dirty, .sleep]
        let small = WidgetBoard.fit(cards, size: .small)
        let medium = WidgetBoard.fit(cards, size: .medium)
        let large = WidgetBoard.fit(cards, size: .large)
        #expect(small.shown == [.formula, .wet])
        #expect(small.hidden == 2)
        #expect(medium.shown == cards)
        #expect(medium.hidden == 0)
        #expect(large.shown == cards)
        #expect(large.hidden == 0)
        #expect(WidgetBoard.unique([.wet, .wet, .formula]).first == .wet)
    }

    @Test func formulaAndPeeStayLabeledAndDoNotInventMillilitres() {
        var care = CareRollup()
        care.lastFormulaAt = now.addingTimeInterval(-30)
        care.lastFormulaML = 120
        care.today.formulaCount = 1
        care.today.formulaML = 120
        care.last24Hours.formulaCount = 2
        care.last24Hours.formulaML = 200
        care.lastWetAt = now.addingTimeInterval(-600)
        care.today.wetCount = 2
        care.last24Hours.wetCount = 3
        care.lastBreastAt = now.addingTimeInterval(-900)
        care.lastBreastSeconds = 900

        let face = WidgetBoard.face(
            babyName: "贝贝",
            care: care,
            recent: [RecentCare(card: .formula, at: now.addingTimeInterval(-30), amountML: 120)],
            reminder: nil,
            cards: [.formula, .wet, .breast, .dirty],
            size: .large,
            language: .zh,
            volume: .milliliters,
            now: now
        )
        let formula = face.items[0]
        let pee = face.items[1]
        let breast = face.items[2]
        #expect(formula.title == "奶粉")
        #expect(formula.sinceLabel == "距上次")
        #expect(formula.sinceValue == "刚刚")
        #expect(formula.lastLabel == "上次")
        #expect(formula.lastValue.contains("120"))
        #expect(formula.todayLabel == "今日")
        #expect(formula.todayValue.contains("1次"))
        #expect(formula.dayValue.contains("2次"))
        #expect(!formula.lastValue.contains("次"))
        #expect(pee.lastValue == "1次")
        #expect(pee.todayValue == "2次")
        #expect(!pee.lastValue.contains("ml"))
        #expect(!pee.accessibilityText.contains("ml"))
        #expect(breast.lastValue.contains("分钟"))
        #expect(!breast.lastValue.contains("ml"))
        let joined = face.items.map(\.accessibilityText).joined(separator: " ")
        #expect(!joined.localizedCaseInsensitiveContains("formula"))
        #expect(!joined.contains("ago"))
        #expect(!joined.contains("Next"))
        #expect(face.reminderLine == nil)
        #expect(!joined.contains("点按"))
        #expect(!joined.contains("换中号"))
        #expect(face.recentLines.first?.contains("120") == true)
        #expect(face.limitNote == nil)

        let small = WidgetBoard.face(
            babyName: "贝贝", care: care, recent: [], reminder: nil,
            cards: [.formula, .wet], size: .small, language: .zh, volume: .milliliters, now: now
        )
        #expect(small.items.count == 2)
        #expect(small.tapHint == nil)
        #expect(small.limitNote == nil)
        #expect(small.reminderLine == nil)
        #expect(small.recentLines.isEmpty)
    }

    @Test func emptyCareDoesNotPretendAnAmount() {
        let face = WidgetBoard.face(
            babyName: "贝贝", care: nil, recent: [], reminder: nil,
            cards: [.formula, .wet], size: .medium, language: .zh, volume: .milliliters, now: now
        )
        #expect(face.items.allSatisfy { $0.lastValue == "还没有" && $0.sinceValue == "还没有" })
        #expect(face.items.allSatisfy { !$0.lastValue.contains("0") && !$0.lastValue.contains("ml") })
        #expect(face.items[0].todayValue == "0次")
    }

    @Test func englishFaceDoesNotUseChinese() {
        var care = CareRollup()
        care.lastFormulaAt = now.addingTimeInterval(-120)
        care.lastFormulaML = 120
        care.today.formulaCount = 1
        care.today.formulaML = 120
        let face = WidgetBoard.face(
            babyName: "Beibei", care: care, recent: [], reminder: nil,
            cards: [.formula], size: .small, language: .en, volume: .milliliters, now: now
        )
        let text = face.items[0].accessibilityText + (face.tapHint ?? "")
        #expect(text.contains("Formula"))
        #expect(text.contains("Since last"))
        #expect(text.contains("ago"))
        #expect(text.contains("120"))
        #expect(!text.contains("奶粉"))
        #expect(!text.contains("分钟"))
        #expect(!text.contains("距上次"))
    }

    @Test func reminderUsesTheUsersWordsAndSkipsANapGuess() {
        let fire = now.addingTimeInterval(3600)
        let rule = CareRuleTemplate.feedInterval(minutes: 60, anchor: .start, text: "该喂奶了")
        var settings = BabyReminderSettings(rules: [rule])
        settings.napWindow.isEnabled = true
        let baby = ReminderBaby(
            id: UUID(),
            name: "贝贝",
            settings: settings,
            lastFeed: nil,
            stamps: [.formula: RecordStamp(start: now, end: now)],
            anyFeed: RecordStamp(start: now, end: now)
        )
        let picked = SnapshotReminderPick.next(for: baby, now: now, calendar: Calendar(identifier: .gregorian))
        #expect(picked?.userWords == true)
        #expect(picked?.text == "该喂奶了")
        #expect(picked?.fireAt != nil)
        let line = WidgetBoard.face(
            babyName: "贝贝", care: nil, recent: [], reminder: picked,
            cards: [.formula], size: .large, language: .zh, volume: .milliliters, now: now
        ).reminderLine
        #expect(line?.contains("该喂奶了") == true)
        #expect(line?.contains("Next") != true)
        _ = fire
    }

    @Test func startLinkOpensAFormAndTimelineDoesNot() {
        let ada = UUID()
        let bo = UUID()
        let pee = DeepLink.start(.wet, babyID: bo)
        let feed = DeepLink.start(.formula, babyID: ada)
        #expect(StartRouting.composer(for: pee) == .editor(.wet))
        #expect(StartRouting.composer(for: feed) == .editor(.formula))
        #expect(StartRouting.composer(for: DeepLink.start(.breast, babyID: ada)) == .editor(.breast))
        #expect(StartRouting.composer(for: DeepLink.timeline(.wet, babyID: ada)) == nil)
        #expect(StartRouting.composer(for: DeepLink.log(.diaper, babyID: ada)) == nil)
        #expect(StartRouting.knownBaby(pee, knownBabyIDs: [ada, bo]))
        #expect(!StartRouting.knownBaby(DeepLink.start(.wet, babyID: UUID()), knownBabyIDs: [ada, bo]))
        #expect(StartRouting.knownBaby(DeepLink.start(.wet, babyID: nil), knownBabyIDs: [ada]))
    }
}
