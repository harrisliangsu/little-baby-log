import SwiftUI
import WidgetKit
import AppIntents
import BabyLogKit

struct FeedingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "FeedingWidget", intent: SelectBabyIntent.self, provider: BabyTimelineProvider()) { entry in
            FeedingWidgetView(entry: entry)
        }
        .configurationDisplayName("喂奶")
        .description("最近一次喂奶。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FeedingWidgetView: View {
    let entry: BabyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let baby = entry.baby {
                switch family {
                case .systemMedium: MediumFeeding(baby: baby, nextFeed: entry.nextFeed, language: entry.language)
                default: SmallFeeding(baby: baby, nextFeed: entry.nextFeed, language: entry.language)
                }
            } else {
                EmptyWidgetView(language: entry.language)
            }
        }
        .widgetBackground()
    }
}

// MARK: Shared info block

/// "Last feed" headline used by both sizes.
private struct FeedSummary: View {
    let baby: WidgetSnapshot.BabySummary
    var compact = false
    var language: ResolvedLanguage = .zh

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let nursing = baby.runningNursing {
                let values = NursingValues(nursing)
                Text(values.isRunning
                     ? (language == .zh ? "亲喂 · \(values.activeSide.map { UICopy.side($0, .zh) } ?? "")" : "Nursing · \(values.activeSide?.title ?? "")")
                     : (language == .zh ? "亲喂暂停" : "Nursing paused"))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(EventKind.breastfeed.color)
                    .widgetAccentable()
                NursingTotalClock(values: values)
                    .font(.system(size: compact ? 36 : 40, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                // A ticking timer Text stretches to the width it's offered, so give each side its own half.
                HStack(spacing: 4) {
                    ForEach(BreastSide.allCases) { side in
                        HStack(spacing: 4) {
                            Text(language == .zh ? UICopy.side(side, .zh) : side.shortLabel)
                            NursingSideClock(values: values, side: side)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.system(size: compact ? 14 : 16, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else if let feed = baby.lastFeed {
                Text(Copy.lastFeed(language))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(feed.kind.color)
                    .widgetAccentable()
                AgoStack(date: feed.referenceDate, language: language)
                    .font(.system(size: compact ? 26 : 32, weight: .bold, design: .rounded))
                if !feed.detail.isEmpty {
                    Text(feed.detail)
                        .font(.system(size: compact ? 15 : 17, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(language == .zh ? "还没有喂奶" : "No feed yet")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Small

private struct SmallFeeding: View {
    let baby: WidgetSnapshot.BabySummary
    let nextFeed: WidgetSnapshot.NextFeed?
    var language: ResolvedLanguage = .zh

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetKindIcon(kind: .breastfeed, size: 26)
                .widgetAccentable()
            Spacer(minLength: 4)
            FeedSummary(baby: baby, compact: true, language: language)
            Spacer(minLength: 4)
            if let side = baby.nextSide, !baby.isNursing {
                HStack(spacing: 6) {
                    Text(language == .zh ? UICopy.side(side, .zh) : side.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(side.color.opacity(0.2)))
                        .foregroundStyle(side.color)
                        .widgetAccentable()
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let nextFeed {
                        Text("~" + PredictionFormat.compactTime(nextFeed.centre))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            } else if let nextFeed {
                Text(PredictionFormat.feedLine(nextFeed, language: language))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(baby.isNursing ? DeepLink.nursing(babyID: baby.id).url : DeepLink.today(babyID: baby.id).url)
    }
}

// MARK: Medium

private struct MediumFeeding: View {
    let baby: WidgetSnapshot.BabySummary
    let nextFeed: WidgetSnapshot.NextFeed?
    var language: ResolvedLanguage = .zh

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetKindIcon(kind: .breastfeed, size: 28)
                    .widgetAccentable()
                Spacer(minLength: 4)
                FeedSummary(baby: baby, language: language)
                Spacer(minLength: 4)
                if !baby.isNursing, let nextFeed {
                    Text(PredictionFormat.feedLine(nextFeed, language: language))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if !baby.isNursing, let side = baby.nextSide {
                    Text(language == .zh ? UICopy.side(side, .zh) : side.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(side.color)
                        .widgetAccentable()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            buttons
                .frame(maxWidth: .infinity)
        }
        .widgetURL(DeepLink.today(babyID: baby.id).url)
    }

    @ViewBuilder
    private var buttons: some View {
        if let nursing = baby.runningNursing {
            let values = NursingValues(nursing)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(BreastSide.allCases) { side in
                        Button(intent: NursingSideIntent(babyID: baby.id, side: side)) {
                            TileLabel(
                                title: language == .zh ? UICopy.side(side, .zh) : side.title,
                                systemImage: values.activeSide == side ? "pause.fill" : "play.fill",
                                tint: side.color,
                                subtitle: DurationFormat.clock(values.banked(side)),
                                liveSince: values.sideReference(side),
                                filled: values.activeSide == side
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button(intent: FinishNursingIntent(babyID: baby.id)) {
                    TileLabel(title: language == .zh ? "完成" : "Done", systemImage: "checkmark", tint: .green, filled: true)
                        .frame(maxHeight: 40)
                }
                .buttonStyle(.plain)
            }
        } else {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(BreastSide.allCases) { side in
                        Button(intent: NursingSideIntent(babyID: baby.id, side: side)) {
                            TileLabel(
                                title: language == .zh ? UICopy.side(side, .zh) : side.title,
                                systemImage: "play.fill",
                                tint: side.color,
                                filled: baby.nextSide == side
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Link(destination: DeepLink.log(.bottle, babyID: baby.id).url) {
                    TileLabel(title: Copy.card(.formula, language), systemImage: EventKind.bottle.symbolName, tint: EventKind.bottle.color)
                        .frame(maxHeight: 40)
                }
            }
        }
    }
}

#Preview("Small", as: .systemSmall) {
    FeedingWidget()
} timeline: {
    BabyEntry.sample()
    BabyEntry.sample(SampleSnapshot.nursing())
    BabyEntry.empty
}

#Preview("Medium", as: .systemMedium) {
    FeedingWidget()
} timeline: {
    BabyEntry.sample()
    BabyEntry.sample(SampleSnapshot.nursing())
    BabyEntry.empty
}
