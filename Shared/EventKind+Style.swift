import SwiftUI
import BabyLogKit

extension EventKind {
    var color: Color {
        switch self {
        case .sleep: return .indigo
        case .breastfeed: return .pink
        case .bottle: return .orange
        case .solids: return .green
        case .diaper: return .teal
        case .pump: return .purple
        case .growth: return .blue
        case .medicine: return .red
        }
    }
}

extension BreastSide {
    /// Left and right get slightly different tints so they are easy to tell apart half asleep.
    var color: Color {
        switch self {
        case .left: return .pink
        case .right: return .purple
        }
    }
}

/// A white SF Symbol on a gradient circle in the kind's color. In the Night theme the colors are dimmed and the
/// symbol is a soft amber instead of white.
struct KindIcon: View {
    @Environment(\.appTheme) private var theme

    let kind: EventKind
    var diaper: DiaperKind?
    var size: CGFloat = 44

    var body: some View {
        let color = theme.color(for: kind)
        RecordGlyph(name: RecordIcons.name(kind: kind, diaper: diaper), color: theme.onColor)
            .frame(width: size * 0.62, height: size * 0.62)
            .frame(width: size, height: size)
            .background(Circle().fill(color))
            .accessibilityHidden(true)
    }
}

enum RecordIcons {
    static func name(kind: EventKind, diaper: DiaperKind? = nil) -> String {
        switch kind {
        case .breastfeed: return "baby"
        case .bottle: return "jar"
        case .solids: return "bowl-food"
        case .sleep: return "moon"
        case .pump: return "drop-half"
        case .growth: return "ruler"
        case .medicine: return "pill"
        case .diaper:
            switch diaper {
            case .wet: return "drop"
            case .dirty, .mixed: return "dirty-mark"
            case .dry, nil: return "diaper-mark"
            }
        }
    }
}

#Preview {
    HStack {
        ForEach(EventKind.allCases) { kind in
            KindIcon(kind: kind, size: 36)
        }
    }
    .padding()
}
