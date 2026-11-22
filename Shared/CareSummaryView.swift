import BabyLogKit
import SwiftUI

/// Summary drawn from a `WidgetSnapshot` baby. The app preview and the widget use this view,
/// so both show the file the app just wrote rather than a fixed example.
struct CareSummaryView: View {
    let baby: WidgetSnapshot.BabySummary
    var language: ResolvedLanguage = .zh

    private var noRecords: Bool {
        if let care = baby.care { return !care.hasAnyRecord }
        return baby.lastFeed == nil && baby.lastDiaperAt == nil && baby.lastSleepEndedAt == nil && baby.runningSleepStartedAt == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if noRecords {
                Text(Copy.noRecords(language))
                    .foregroundStyle(.secondary)
            }
            labeled(Copy.lastFeed(language), date: baby.care?.lastFeedAt ?? baby.lastFeed?.referenceDate)
            labeled(Copy.lastDiaper(language), date: baby.care?.lastDiaperAt ?? baby.lastDiaperAt)
            labeled(
                Copy.lastSleep(language),
                date: baby.care?.lastSleepAt ?? baby.runningSleepStartedAt ?? baby.lastSleepEndedAt,
                running: baby.care?.sleepRunning == true || baby.runningSleepStartedAt != nil
            )
            if let care = baby.care {
                Text(Copy.widgetLine(Copy.todayWord(language), care.today, language))
                Text(Copy.widgetLine(Copy.last24(language), care.last24Hours, language))
            }
        }
        .font(.body.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("widget-summary")
    }

    private func labeled(_ title: String, date: Date?, running: Bool = false) -> some View {
        let value: String
        if running, title == Copy.lastSleep(language) {
            value = Copy.sleeping(language)
        } else if let date {
            value = Copy.ago(date, language)
        } else {
            value = Copy.none(language)
        }
        return Text("\(title) \(value)")
    }
}
