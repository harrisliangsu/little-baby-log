import BabyLogKit
import SwiftUI
import WidgetKit

/// Home Screen board for one baby and an ordered list of care items.
/// Each item is a link to its form. systemSmall may still offer only one system tap.
/// https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-screens
struct CareBoardWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CareBoardWidget", intent: CareBoardIntent.self, provider: CareBoardProvider()) { entry in
            CareBoardWidgetView(entry: entry)
        }
        .configurationDisplayName("宝宝小记")
        .description("最多 6 个已选项目都会显示。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CareBoardEntry: TimelineEntry {
    var date: Date
    var baby: WidgetSnapshot.BabySummary?
    var missingBaby: Bool
    var language: ResolvedLanguage
    var cards: [HomeCard]
    var volumeUnit: VolumeUnit
}

struct CareBoardWidgetView: View {
    var entry: CareBoardEntry
    @Environment(\.widgetFamily) private var family

    private var size: WidgetSize {
        switch family {
        case .systemMedium: return .medium
        case .systemLarge: return .large
        default: return .small
        }
    }

    private var face: WidgetFace {
        WidgetFace.make(
            baby: entry.baby,
            cards: entry.cards,
            size: size,
            language: entry.language,
            volume: entry.volumeUnit,
            now: entry.date,
            missingBaby: entry.missingBaby
        )
    }

    var body: some View {
        Group {
            if entry.baby == nil && !entry.missingBaby {
                EmptyWidgetView(language: entry.language)
            } else {
                CareBoardFace(face: face, size: size) { card in
                    DeepLink.start(card, babyID: entry.missingBaby ? nil : entry.baby?.id).url
                }
            }
        }
        .widgetBackground()
    }
}

struct CareBoardProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CareBoardEntry {
        CareBoardEntry(date: .now, baby: nil, missingBaby: false, language: .zh, cards: [.formula, .wet], volumeUnit: .milliliters)
    }

    func snapshot(for configuration: CareBoardIntent, in context: Context) async -> CareBoardEntry {
        load(configuration)
    }

    /// Relative phrases are plain strings in the app language, so the timeline moves them forward.
    /// The system date styles would follow the phone language and split "0 minutes" from "ago".
    func timeline(for configuration: CareBoardIntent, in context: Context) async -> Timeline<CareBoardEntry> {
        let first = load(configuration)
        var dates: [Date] = []
        for minutes in [1, 5, 15, 30, 60, 180] {
            if let date = Calendar.current.date(byAdding: .minute, value: minutes, to: first.date) {
                dates.append(date)
            }
        }
        if let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: first.date)) {
            dates.append(midnight)
        }
        if let fire = first.baby?.nextReminder?.fireAt, fire > first.date {
            dates.append(fire)
        }
        var entries = [first]
        for date in Set(dates).sorted() where date > first.date {
            var copy = first
            copy.date = date
            entries.append(copy)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func load(_ configuration: CareBoardIntent) -> CareBoardEntry {
        guard let url = AppGroup.snapshotURL, let snapshot = WidgetSnapshot.read(from: url) else {
            return CareBoardEntry(date: .now, baby: nil, missingBaby: false, language: .zh, cards: configuration.cards, volumeUnit: .milliliters)
        }
        if let id = configuration.baby?.uuid {
            guard let baby = snapshot.babies.first(where: { $0.id == id }) else {
                return CareBoardEntry(
                    date: .now,
                    baby: nil,
                    missingBaby: true,
                    language: snapshot.resolvedLanguage,
                    cards: configuration.cards,
                    volumeUnit: snapshot.volumeUnit
                )
            }
            return CareBoardEntry(date: .now, baby: baby, missingBaby: false, language: snapshot.resolvedLanguage, cards: configuration.cards, volumeUnit: snapshot.volumeUnit)
        }
        return CareBoardEntry(
            date: .now,
            baby: snapshot.baby(id: nil),
            missingBaby: false,
            language: snapshot.resolvedLanguage,
            cards: configuration.cards,
            volumeUnit: snapshot.volumeUnit
        )
    }
}
