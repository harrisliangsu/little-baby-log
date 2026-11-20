import BabyLogKit
import SwiftUI

/// Formula, nursing, pee, poop, diaper change, and sleep. Each card logs with + and shows
/// time since the last record, today's count, and the rolling 24-hour count. Formula also totals ml.
struct CareCardsView: View {
    @ObservedObject var baby: Baby

    let onFormula: () -> Void
    let onBreast: () -> Void
    let onSleep: () -> Void
    let onDiaper: (DiaperKind) -> Void

    @Environment(\.managedObjectContext) private var context
    @Environment(\.appTheme) private var theme
    @FetchRequest private var events: FetchedResults<LogEvent>
    @State private var changeTick = 0

    init(
        baby: Baby,
        onFormula: @escaping () -> Void,
        onBreast: @escaping () -> Void,
        onSleep: @escaping () -> Void,
        onDiaper: @escaping (DiaperKind) -> Void
    ) {
        self.baby = baby
        self.onFormula = onFormula
        self.onBreast = onBreast
        self.onSleep = onSleep
        self.onDiaper = onDiaper
        _events = FetchRequest(fetchRequest: LogEvent.requestAll(baby: baby))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let _ = changeTick
            let care = CareRollup.make(events: Array(events), now: timeline.date)
            VStack(spacing: 12) {
                card(
                    title: "亲喂",
                    symbol: EventKind.breastfeed.symbolName,
                    tint: EventKind.breastfeed.color,
                    addID: "add-breast",
                    summaryID: "summary-breast",
                    recent: recent(care.lastBreastAt, now: timeline.date),
                    today: Zh.count(care.today.breastCount),
                    last24: Zh.count(care.last24Hours.breastCount),
                    action: onBreast
                )
                card(
                    title: "奶粉",
                    symbol: EventKind.bottle.symbolName,
                    tint: EventKind.bottle.color,
                    addID: "add-formula",
                    summaryID: "summary-formula",
                    recent: recent(care.lastFormulaAt, now: timeline.date),
                    today: "\(Zh.count(care.today.formulaCount)) · \(Zh.ml(care.today.formulaML))",
                    last24: "\(Zh.count(care.last24Hours.formulaCount)) · \(Zh.ml(care.last24Hours.formulaML))",
                    action: onFormula
                )
                card(
                    title: "小便",
                    symbol: DiaperKind.wet.symbolName,
                    tint: EventKind.diaper.color,
                    addID: "add-wet",
                    summaryID: "summary-wet",
                    recent: recent(care.lastWetAt, now: timeline.date),
                    today: Zh.count(care.today.wetCount),
                    last24: Zh.count(care.last24Hours.wetCount),
                    action: { onDiaper(.wet) }
                )
                card(
                    title: "大便",
                    symbol: DiaperKind.dirty.symbolName,
                    tint: Color.brown,
                    addID: "add-dirty",
                    summaryID: "summary-dirty",
                    recent: recent(care.lastDirtyAt, now: timeline.date),
                    today: Zh.count(care.today.dirtyCount),
                    last24: Zh.count(care.last24Hours.dirtyCount),
                    action: { onDiaper(.dirty) }
                )
                card(
                    title: "换尿布",
                    symbol: DiaperKind.dry.symbolName,
                    tint: EventKind.diaper.color,
                    addID: "add-diaper-change",
                    summaryID: "summary-change",
                    recent: recent(care.lastDiaperChangeAt, now: timeline.date),
                    today: Zh.count(care.today.diaperChangeCount),
                    last24: Zh.count(care.last24Hours.diaperChangeCount),
                    action: { onDiaper(.dry) }
                )
                card(
                    title: "睡眠",
                    symbol: EventKind.sleep.symbolName,
                    tint: EventKind.sleep.color,
                    addID: "add-sleep",
                    summaryID: "summary-sleep",
                    recent: care.sleepRunning ? Zh.sleepingNow : recent(care.lastSleepAt, now: timeline.date),
                    today: Zh.count(care.today.sleepCount),
                    last24: Zh.count(care.last24Hours.sleepCount),
                    action: onSleep
                )
            }
        }
        .onContextChange(context) { changeTick += 1 }
    }

    private func recent(_ date: Date?, now: Date) -> String {
        guard let date else { return Zh.recentNone }
        return Zh.ago(date, now: now)
    }

    private func card(
        title: String,
        symbol: String,
        tint: Color,
        addID: String,
        summaryID: String,
        recent: String,
        today: String,
        last24: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(tint))
                Text(title)
                    .font(.headline)
                Spacer(minLength: 8)
                Button(action: action) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier(addID)
                .accessibilityLabel("添加\(title)")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("最近 \(recent)")
                Text("今日 \(today)")
                Text("24小时 \(last24)")
            }
            .font(.subheadline)
            .foregroundStyle(theme.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(summaryID)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
