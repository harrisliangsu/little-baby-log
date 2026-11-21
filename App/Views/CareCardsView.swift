import BabyLogKit
import SwiftUI

/// One card per chosen category. The card body opens that timeline. + adds a record.
struct CareCardsView: View {
    @ObservedObject var baby: Baby

    let onOpen: (HomeCard) -> Void
    let onAdd: (HomeCard) -> Void

    @Environment(\.managedObjectContext) private var context
    @Environment(\.appTheme) private var theme
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @AppStorage(HomeLayoutStore.storageKey) private var layoutJSON = ""
    @FetchRequest private var events: FetchedResults<LogEvent>
    @State private var changeTick = 0

    init(baby: Baby, onOpen: @escaping (HomeCard) -> Void, onAdd: @escaping (HomeCard) -> Void) {
        self.baby = baby
        self.onOpen = onOpen
        self.onAdd = onAdd
        _events = FetchRequest(fetchRequest: LogEvent.requestAll(baby: baby))
    }

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let _ = changeTick
            let care = CareRollup.make(events: Array(events), now: timeline.date)
            let recorded = HomeCardMatch.recordedCards(in: Array(events))
            let cards = currentLayout.resolved(recorded: recorded)
            VStack(spacing: 8) {
                Text(compactSummary(cards, care: care, now: timeline.date))
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("home-compact-summary")
                ForEach(cards) { card in
                    row(card, care: care, now: timeline.date)
                }
            }
        }
        .onContextChange(context) { changeTick += 1 }
    }

    private var currentLayout: BabyHomeLayout {
        guard let id = baby.uuid else { return BabyHomeLayout() }
        let data = layoutJSON.isEmpty ? nil : Data(layoutJSON.utf8)
        return HomeLayoutStore.load(babyID: id, from: data)
    }

    private func compactSummary(_ cards: [HomeCard], care: CareRollup, now: Date) -> String {
        cards.map { "\(Copy.card($0, language)) \(recent($0, care: care, now: now))" }.joined(separator: " · ")
    }

    private func row(_ card: HomeCard, care: CareRollup, now: Date) -> some View {
        let title = Copy.card(card, language)
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol(card))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint(card)))
            Button {
                onOpen(card)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                    Text("\(Copy.recent(language)) \(recent(card, care: care, now: now)) · \(Copy.todayWord(language)) \(todayLine(card, care: care)) · \(Copy.last24(language)) \(dayLine(card, window: care.last24Hours))")
                        .font(.footnote)
                        .foregroundStyle(theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(summaryID(card))
            Button {
                onAdd(card)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier(addID(card))
            .accessibilityLabel(language == .zh ? "添加\(title)" : "Add \(title)")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func recent(_ card: HomeCard, care: CareRollup, now: Date) -> String {
        if card == .sleep, care.sleepRunning { return Copy.sleeping(language) }
        let date: Date?
        switch card {
        case .breast: date = care.lastBreastAt
        case .formula: date = care.lastFormulaAt
        case .wet: date = care.lastWetAt
        case .dirty: date = care.lastDirtyAt
        case .diaperChange: date = care.lastDiaperChangeAt
        case .sleep: date = care.lastSleepAt
        }
        guard let date else { return Copy.none(language) }
        var text = Copy.ago(date, now: now, language)
        if card == .breast, let seconds = care.lastBreastSeconds, seconds > 0 {
            text += " · " + Copy.duration(seconds, language)
        }
        if card == .formula, care.today.formulaML > 0, let amount = lastFormulaAmount() {
            text += " · " + Copy.ml(amount, language)
        }
        return text
    }

    private func lastFormulaAmount() -> Double? {
        events.first { HomeCardMatch.matches($0, card: .formula) }?.amountML
    }

    private func todayLine(_ card: HomeCard, care: CareRollup) -> String {
        dayLine(card, window: care.today)
    }

    private func dayLine(_ card: HomeCard, window: CareRollup.Window) -> String {
        switch card {
        case .breast: return Copy.count(window.breastCount, language)
        case .formula: return "\(Copy.count(window.formulaCount, language)) · \(Copy.ml(window.formulaML, language))"
        case .wet: return Copy.count(window.wetCount, language)
        case .dirty: return Copy.count(window.dirtyCount, language)
        case .diaperChange: return Copy.count(window.diaperChangeCount, language)
        case .sleep: return Copy.count(window.sleepCount, language)
        }
    }

    private func symbol(_ card: HomeCard) -> String {
        switch card {
        case .breast: return EventKind.breastfeed.symbolName
        case .formula: return EventKind.bottle.symbolName
        case .wet: return DiaperKind.wet.symbolName
        case .dirty: return DiaperKind.dirty.symbolName
        case .diaperChange: return DiaperKind.dry.symbolName
        case .sleep: return EventKind.sleep.symbolName
        }
    }

    private func tint(_ card: HomeCard) -> Color {
        switch card {
        case .breast: return EventKind.breastfeed.color
        case .formula: return EventKind.bottle.color
        case .dirty: return .brown
        case .wet, .diaperChange: return EventKind.diaper.color
        case .sleep: return EventKind.sleep.color
        }
    }

    private func addID(_ card: HomeCard) -> String {
        switch card {
        case .breast: return "add-breast"
        case .formula: return "add-formula"
        case .wet: return "add-wet"
        case .dirty: return "add-dirty"
        case .diaperChange: return "add-diaper-change"
        case .sleep: return "add-sleep"
        }
    }

    private func summaryID(_ card: HomeCard) -> String {
        switch card {
        case .breast: return "summary-breast"
        case .formula: return "summary-formula"
        case .wet: return "summary-wet"
        case .dirty: return "summary-dirty"
        case .diaperChange: return "summary-change"
        case .sleep: return "summary-sleep"
        }
    }

}
