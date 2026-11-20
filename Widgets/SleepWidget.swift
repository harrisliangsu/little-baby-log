import SwiftUI
import WidgetKit
import AppIntents
import BabyLogKit

struct SleepWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SleepWidget", intent: SelectBabyIntent.self, provider: BabyTimelineProvider()) { entry in
            SleepWidgetView(entry: entry)
        }
        .configurationDisplayName("睡眠")
        .description("How long your baby has been awake or asleep, the next nap window, and a Sleep / Wake up button.")
        .supportedFamilies([.systemSmall])
    }
}

struct SleepWidgetView: View {
    let entry: BabyEntry

    var body: some View {
        Group {
            if let baby = entry.baby {
                content(baby)
            } else {
                EmptyWidgetView()
            }
        }
        .widgetBackground()
    }

    private func content(_ baby: WidgetSnapshot.BabySummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                WidgetKindIcon(kind: .sleep, size: 22)
                    .widgetAccentable()
                Text(baby.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            VStack(alignment: .leading, spacing: 2) {
                if let started = baby.runningSleepStartedAt {
                    Text("睡眠中")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(EventKind.sleep.color)
                        .widgetAccentable()
                    Elapsed.since(started)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                } else if let ended = baby.lastSleepEndedAt {
                    Text("醒了")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                        .widgetAccentable()
                    Elapsed.since(ended)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("还没有睡眠")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                if let next = entry.nextSleep {
                    Text(PredictionFormat.sleepLine(next))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 2)
                }
            }
            .multilineTextAlignment(.leading)

            Spacer(minLength: 6)

            Button(intent: ToggleSleepIntent(babyID: baby.id)) {
                TileLabel(
                    title: baby.isSleeping ? "醒来" : "睡眠",
                    systemImage: baby.isSleeping ? "sun.max.fill" : EventKind.sleep.symbolName,
                    tint: baby.isSleeping ? .orange : EventKind.sleep.color,
                    filled: true
                )
                .frame(height: entry.nextSleep == nil ? 38 : 34)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(DeepLink.today(babyID: baby.id).url)
    }
}

#Preview("Awake", as: .systemSmall) {
    SleepWidget()
} timeline: {
    BabyEntry.sample()
    BabyEntry.sample(SampleSnapshot.sleeping())
}
