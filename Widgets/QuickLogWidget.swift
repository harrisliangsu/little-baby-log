import SwiftUI
import WidgetKit
import AppIntents
import BabyLogKit

struct QuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "QuickLogWidget", intent: SelectBabyIntent.self, provider: BabyTimelineProvider()) { entry in
            QuickLogWidgetView(entry: entry)
        }
        .configurationDisplayName("宝宝小记")
        .description("最近的喂奶、尿布和睡眠，以及今日和 24 小时汇总。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct QuickLogWidgetView: View {
    let entry: BabyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let baby = entry.baby {
                content(baby)
            } else {
                EmptyWidgetView(language: entry.language)
            }
        }
        .widgetBackground()
    }

    private func content(_ baby: WidgetSnapshot.BabySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(baby)
            if family == .systemLarge {
                details(baby)
            }
            grid(baby)
        }
        .widgetURL(DeepLink.today(babyID: baby.id).url)
    }

    private func header(_ baby: WidgetSnapshot.BabySummary) -> some View {
        HStack(spacing: 6) {
            if let nursing = baby.runningNursing {
                let values = NursingValues(nursing)
                Label {
                    NursingTotalClock(values: values)
                } icon: {
                    Image(systemName: EventKind.breastfeed.symbolName)
                }
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(EventKind.breastfeed.color)
                .widgetAccentable()
            } else if let started = baby.runningSleepStartedAt {
                Label {
                    Elapsed.since(started)
                } icon: {
                    Image(systemName: EventKind.sleep.symbolName)
                }
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(EventKind.sleep.color)
                .lineLimit(1)
                .widgetAccentable()
            } else if let feed = baby.lastFeed {
                AgoLine(prefix: Copy.lastFeed(entry.language), date: feed.referenceDate, language: entry.language)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Large only: the same lines the app writes into the snapshot. No sample baby.
    private func details(_ baby: WidgetSnapshot.BabySummary) -> some View {
                CareSummaryView(baby: baby, language: entry.language)
            .padding(.vertical, 2)
    }

    // MARK: Buttons

    private func grid(_ baby: WidgetSnapshot.BabySummary) -> some View {
        let values = baby.runningNursing.map(NursingValues.init)
        return Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                ForEach(BreastSide.allCases) { side in
                    Button(intent: NursingSideIntent(babyID: baby.id, side: side)) {
                        TileLabel(
                            title: (entry.language == .zh ? "亲喂" : "Nurse ") + (side == .left ? (entry.language == .zh ? "左" : "L") : (entry.language == .zh ? "右" : "R")),
                            systemImage: values?.activeSide == side ? "pause.fill" : EventKind.breastfeed.symbolName,
                            tint: side.color,
                            filled: values?.activeSide == side || (values == nil && baby.nextSide == side)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Button(intent: ToggleSleepIntent(babyID: baby.id)) {
                    TileLabel(
                        title: baby.isSleeping ? (entry.language == .zh ? "醒来" : "Wake") : Copy.card(.sleep, entry.language),
                        systemImage: baby.isSleeping ? "sun.max.fill" : EventKind.sleep.symbolName,
                        tint: baby.isSleeping ? .orange : EventKind.sleep.color,
                        filled: baby.isSleeping
                    )
                }
                .buttonStyle(.plain)
            }
            GridRow {
                Button(intent: LogDiaperIntent(babyID: baby.id, kind: .wet)) {
                    TileLabel(title: Copy.card(.wet, entry.language), systemImage: DiaperKind.wet.symbolName, tint: EventKind.diaper.color)
                }
                .buttonStyle(.plain)
                Button(intent: LogDiaperIntent(babyID: baby.id, kind: .dirty)) {
                    TileLabel(title: Copy.card(.dirty, entry.language), systemImage: DiaperKind.dirty.symbolName, tint: .brown)
                }
                .buttonStyle(.plain)
                Link(destination: DeepLink.log(.bottle, babyID: baby.id).url) {
                    TileLabel(title: Copy.card(.formula, entry.language), systemImage: EventKind.bottle.symbolName, tint: EventKind.bottle.color)
                }
            }
        }
        .frame(maxHeight: family == .systemLarge ? 150 : .infinity)
    }
}

#Preview("Medium", as: .systemMedium) {
    QuickLogWidget()
} timeline: {
    BabyEntry.sample()
    BabyEntry.sample(SampleSnapshot.nursing())
}

#Preview("Large", as: .systemLarge) {
    QuickLogWidget()
} timeline: {
    BabyEntry.sample()
    BabyEntry.sample(SampleSnapshot.sleeping())
}
