import BabyLogKit
import SwiftUI

/// Layout follows how many items are selected. One item is large; two or more share compact rows.
/// Each row is a link. systemSmall may still expose only one system tap.
struct CareBoardFace: View {
    var face: WidgetFace
    var size: WidgetSize
    var destination: ((HomeCard) -> URL)?
    var marksSizeIdentifier = true

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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier(marksSizeIdentifier ? "widget-face-\(size.rawValue)" : "widget-sample-face")
    }

    /// One selected item is the headline. Two or more stay one full-width line each, so a small widget still shows every pick.
    private var small: some View { sized(columns: 1, showsToday: false) }

    private var medium: some View { sized(columns: 1, showsToday: true) }

    private var large: some View {
        VStack(alignment: .leading, spacing: 6) {
            sized(columns: 1, showsToday: true)
            if let title = face.recentTitle {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(face.recentLines, id: \.self) { Text($0).font(.subheadline).lineLimit(2).minimumScaleFactor(0.8) }
            }
            if let reminder = face.reminderLine {
                Text(reminder).font(.subheadline).lineLimit(2).minimumScaleFactor(0.8)
            }
        }
    }

    private func sized(columns: Int, showsToday: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if columns > 1 {
                let rows = stride(from: 0, to: face.items.count, by: columns).map { start in
                    Array(face.items[start..<min(start + columns, face.items.count)])
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        ForEach(row, id: \.card) { item in
                            itemLink(item, showsToday: showsToday)
                        }
                    }
                }
            } else {
                ForEach(face.items, id: \.card) { item in
                    itemLink(item, showsToday: showsToday)
                }
            }
            if let note = face.limitNote {
                Text(note)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private func itemLink(_ item: WidgetFaceItem, showsToday: Bool) -> some View {
        linked(item.card) {
            Group {
                if face.items.count == 1 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.title3.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.8)
                        Text(item.sinceValue).font(.title.weight(.bold)).lineLimit(2).minimumScaleFactor(0.85)
                        Text(item.lastValue).font(.title3).lineLimit(2).minimumScaleFactor(0.85)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(item.title)
                            .font(rowFont.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(item.sinceValue)
                            .font(rowFont.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .layoutPriority(1)
                            .frame(maxWidth: .infinity, alignment: .center)
                        Text(item.lastValue)
                            .font(rowFont)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .layoutPriority(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        if showsToday {
                            Text(item.todayValue)
                                .font(rowFont)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, minHeight: face.items.count <= 2 ? 28 : 20, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(item.accessibilityText)
            .accessibilityIdentifier("widget-item-\(item.card.rawValue)")
        }
    }

    /// Fewer picks use a larger line. Six picks stay at subheadline, above the old caption2 that scaled to about half.
    private var rowFont: Font {
        switch face.items.count {
        case ...2: return .title3
        case 3...4: return .body
        default: return .subheadline
        }
    }

    private var spoken: String {
        var parts = face.items.map(\.accessibilityText)
        if let hint = face.tapHint { parts.append(hint) }
        if let note = face.limitNote { parts.append(note) }
        if let line = face.reminderLine { parts.append(line) }
        parts.append(contentsOf: face.recentLines)
        if let missing = face.missingBaby { parts.append(missing) }
        return parts.joined(separator: " ")
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
