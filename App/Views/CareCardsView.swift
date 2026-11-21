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
            VStack(spacing: 12) {
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

    private func row(_ card: HomeCard, care: CareRollup, now: Date) -> some View {
        let title = Copy.card(card, language)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: symbol(card))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(tint(card)))
                Text(title)
                    .font(.headline)
                Spacer(minLength: 8)
                Button {
                    onAdd(card)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier(addID(card))
                .accessibilityLabel(language == .zh ? "添加\(title)" : "Add \(title)")
            }
            Button {
                onOpen(card)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Copy.recent(language)) \(recent(card, care: care, now: now))")
                    Text("\(Copy.todayWord(language)) \(todayLine(card, care: care))")
                    Text("\(Copy.last24(language)) \(dayLine(card, window: care.last24Hours))")
                }
                .font(.subheadline)
                .foregroundStyle(theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(summaryID(card))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
