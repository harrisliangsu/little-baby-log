import BabyLogKit
import SwiftUI

/// One function. The body opens its timeline. Plus opens a new form. They do not share a hit target.
struct CareCardRow: View {
    let card: HomeCard
    var prominent: Bool
    var detailed: Bool
    var care: CareRollup
    var now: Date
    let onOpen: () -> Void
    let onAdd: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.uiLanguage) private var language
    @AppStorage(Prefs.volumeUnit) private var volume: VolumeUnit = Prefs.defaultVolumeUnit

    var body: some View {
        let face = CardFaces.make(
            card: card,
            care: care,
            detailed: detailed,
            language: language,
            volume: volume,
            now: now
        )
        let title = Copy.card(card, language)
        let iconSide: CGFloat = prominent ? 44 : 28
        let plusSide: CGFloat = prominent ? 56 : 44
        HStack(alignment: .center, spacing: prominent ? 12 : 8) {
            RecordGlyph(name: RecordIcons.name(kind: symbolKind, diaper: symbolDiaper), color: .white)
                .frame(width: iconSide * 0.62, height: iconSide * 0.62)
                .frame(width: iconSide, height: iconSide)
                .background(Circle().fill(tint))
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: prominent ? 4 : 2) {
                    Text(title)
                        .font(prominent ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                    Text(face.primary)
                        .font(prominent ? .title3 : .subheadline)
                        .foregroundStyle(theme.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    if let detail = face.detail {
                        Text(detail)
                            .font(prominent ? .body : .footnote)
                            .foregroundStyle(theme.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: prominent ? 72 : 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(summaryID)
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(prominent ? .largeTitle : .title2)
                    .frame(width: plusSide, height: plusSide)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier(addID)
            .accessibilityLabel(language == .zh ? "添加\(title)" : "Add \(title)")
        }
        .padding(.vertical, prominent ? 12 : 6)
        .padding(.horizontal, prominent ? 14 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: prominent ? 18 : 12, style: .continuous))
    }

    private var symbolKind: EventKind {
        switch card {
        case .breast: return .breastfeed
        case .formula: return .bottle
        case .wet, .dirty, .diaperChange: return .diaper
        case .sleep: return .sleep
        }
    }

    private var symbolDiaper: DiaperKind? {
        switch card {
        case .wet: return .wet
        case .dirty: return .dirty
        case .diaperChange: return .dry
        default: return nil
        }
    }

    private var symbol: String {
        switch card {
        case .breast: return EventKind.breastfeed.symbolName
        case .formula: return EventKind.bottle.symbolName
        case .wet: return DiaperKind.wet.symbolName
        case .dirty: return DiaperKind.dirty.symbolName
        case .diaperChange: return DiaperKind.dry.symbolName
        case .sleep: return EventKind.sleep.symbolName
        }
    }

    private var tint: Color {
        switch card {
        case .breast: return EventKind.breastfeed.color
        case .formula: return EventKind.bottle.color
        case .dirty: return .brown
        case .wet, .diaperChange: return EventKind.diaper.color
        case .sleep: return EventKind.sleep.color
        }
    }

    private var addID: String {
        switch card {
        case .breast: return "add-breast"
        case .formula: return "add-formula"
        case .wet: return "add-wet"
        case .dirty: return "add-dirty"
        case .diaperChange: return "add-diaper-change"
        case .sleep: return "add-sleep"
        }
    }

    private var summaryID: String {
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

/// Functions that are not in the record area. One icon opens that form. No summary row and no extra plus.
struct OtherLogStrip: View {
    let cards: [HomeCard]
    let kinds: [EventKind]
    let onCard: (HomeCard) -> Void
    let onKind: (EventKind) -> Void
    var onHistory: ((EventKind) -> Void)? = nil

    @Environment(\.uiLanguage) private var language

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(cards) { card in
                iconButton(
                    icon: RecordIcons.name(kind: kind(card), diaper: diaper(card)),
                    tint: tint(card),
                    title: Copy.card(card, language),
                    identifier: addID(card),
                    action: { onCard(card) }
                )
            }
            ForEach(kinds) { kind in
                iconButton(
                    icon: RecordIcons.name(kind: kind),
                    tint: kind.color,
                    title: UICopy.kind(kind, language),
                    identifier: "add-\(kind.rawValue)",
                    action: { onKind(kind) }
                )
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("other-log-icons")
    }

    private func iconButton(
        icon: String,
        tint: Color,
        title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RecordGlyph(name: icon, color: .white)
                    .frame(width: 26, height: 26)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Circle().fill(tint))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                if let onHistory, let kind = EventKind(rawValue: String(identifier.dropFirst(4))), OtherLogKinds.kinds.contains(kind) {
                    Button(language == .zh ? "记录" : "History") {
                        onHistory(kind)
                    }
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier(identifier.replacingOccurrences(of: "add-", with: "history-"))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .contentShape(Rectangle())
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(language == .zh ? "添加\(title)" : "Add \(title)")
    }

    private func kind(_ card: HomeCard) -> EventKind {
        switch card {
        case .breast: return .breastfeed
        case .formula: return .bottle
        case .wet, .dirty, .diaperChange: return .diaper
        case .sleep: return .sleep
        }
    }

    private func diaper(_ card: HomeCard) -> DiaperKind? {
        switch card {
        case .wet: return .wet
        case .dirty: return .dirty
        case .diaperChange: return .dry
        default: return nil
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
}

enum OtherLogKinds {
    /// Event kinds that are not one of the home cards. They only appear in the other-log area.
    static let kinds: [EventKind] = [.solids, .pump, .growth, .medicine]
}
