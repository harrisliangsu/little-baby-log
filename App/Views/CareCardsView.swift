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
            Image(systemName: symbol)
                .font((prominent ? Font.title3 : Font.caption).weight(.semibold))
                .foregroundStyle(.white)
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

/// A function that is not a home card. The whole row opens its form.
struct OtherKindRow: View {
    let kind: EventKind
    let onAdd: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.uiLanguage) private var language

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 10) {
                KindIcon(kind: kind, size: 28)
                Text(UICopy.kind(kind, language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer(minLength: 8)
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("add-\(kind.rawValue)")
        .accessibilityLabel(language == .zh ? "添加\(UICopy.kind(kind, language))" : "Add \(UICopy.kind(kind, language))")
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

enum OtherLogKinds {
    /// Event kinds that are not one of the home cards. They only appear in the other-log area.
    static let kinds: [EventKind] = [.solids, .pump, .growth, .medicine]
}
