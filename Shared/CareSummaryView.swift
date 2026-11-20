import BabyLogKit
import SwiftUI

/// Summary drawn from a `WidgetSnapshot` baby. The app preview and the widget use this view,
/// so both show the file the app just wrote rather than a fixed example.
struct CareSummaryView: View {
    let baby: WidgetSnapshot.BabySummary

    private var noRecords: Bool {
        if let care = baby.care { return !care.hasAnyRecord }
        return baby.lastFeed == nil && baby.lastDiaperAt == nil && baby.lastSleepEndedAt == nil && baby.runningSleepStartedAt == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(baby.name)
                .font(.headline)
            if noRecords {
                Text(Zh.noRecords)
                    .foregroundStyle(.secondary)
            }
            labeled("最近喂奶", date: baby.care?.lastFeedAt ?? baby.lastFeed?.referenceDate)
            labeled("最近尿布", date: baby.care?.lastDiaperAt ?? baby.lastDiaperAt)
            labeled(
                "最近睡眠",
                date: baby.care?.lastSleepAt ?? baby.runningSleepStartedAt ?? baby.lastSleepEndedAt,
                running: baby.care?.sleepRunning == true || baby.runningSleepStartedAt != nil
            )
            if let care = baby.care {
                Text(Zh.widgetLine("今日", care.today))
                Text(Zh.widgetLine("24小时", care.last24Hours))
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("widget-summary")
    }

    private func labeled(_ title: String, date: Date?, running: Bool = false) -> some View {
        let value: String
        if running, title == "最近睡眠" {
            value = Zh.sleepingNow
        } else if let date {
            value = Zh.ago(date)
        } else {
            value = Zh.recentNone
        }
        return Text("\(title) \(value)")
    }
}
