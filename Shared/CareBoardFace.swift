import BabyLogKit
import SwiftUI

/// Three different Home Screen layouts. They share the same words and the same limits.
/// A small widget does not embed links: the system gives it one tap target, applied by the widget with `widgetURL`.
struct CareBoardFace: View {
    var face: WidgetFace
    var size: WidgetSize
    var destination: ((HomeCard) -> URL)?

    var body: some View {
        Group {
            if let missing = face.missingBaby {
                missingView(missing)
            } else if let prompt = face.chooseItems {
                missingView(prompt)
            } else {
                switch size {
                case .small: small
                case .medium: medium
                case .large: large
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("widget-face-\(size.rawValue)")
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            name
            if let item = face.items.first {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                labeled(item.sinceLabel, item.sinceValue, prominent: true)
                labeled(item.lastLabel, item.lastValue, prominent: true)
            }
            Spacer(minLength: 2)
            if let hint = face.tapHint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            limit
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            name
            HStack(alignment: .top, spacing: 8) {
                ForEach(face.items, id: \.card) { item in
                    linked(item.card) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            labeled(item.sinceLabel, item.sinceValue, prominent: false)
                            labeled(item.lastLabel, item.lastValue, prominent: false)
                            labeled(item.todayLabel, item.todayValue, prominent: false)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(item.accessibilityText)
                    }
                }
            }
            Spacer(minLength: 0)
            limit
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            name
            ForEach(face.items, id: \.card) { item in
                linked(item.card) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            labeled(item.sinceLabel, item.sinceValue, prominent: false)
                            labeled(item.lastLabel, item.lastValue, prominent: false)
                        }
                        HStack(spacing: 8) {
                            labeled(item.todayLabel, item.todayValue, prominent: false)
                            labeled(item.dayLabel, item.dayValue, prominent: false)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(item.accessibilityText)
                }
            }
            if let title = face.recentTitle {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(face.recentLines, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .lineLimit(2)
                }
            }
            if let reminder = face.reminderLine {
                Text(reminder)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
            }
            limit
            Spacer(minLength: 0)
        }
    }

    private var name: some View {
        Text(face.babyName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var limit: some View {
        if let note = face.limitNote {
            Text(note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func labeled(_ label: String, _ value: String, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(prominent ? .title3.weight(.bold) : .caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    private func missingView(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .multilineTextAlignment(.leading)
            .lineLimit(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func linked<Content: View>(_ card: HomeCard, @ViewBuilder content: () -> Content) -> some View {
        if let destination {
            Link(destination: destination(card)) { content() }
        } else {
            content()
        }
    }
}

extension WidgetFace {
    static func make(
        baby: WidgetSnapshot.BabySummary?,
        cards: [HomeCard],
        size: WidgetSize,
        language: ResolvedLanguage,
        volume: VolumeUnit,
        now: Date,
        missingBaby: Bool
    ) -> WidgetFace {
        if missingBaby { return WidgetBoard.missing(language: language) }
        return WidgetBoard.face(
            babyName: baby?.name ?? "",
            care: baby?.care,
            recent: baby?.recent ?? [],
            reminder: baby?.nextReminder,
            cards: cards,
            size: size,
            language: language,
            volume: volume,
            now: now
        )
    }
}
