import SwiftUI
import BabyLogKit

/// One line in a timeline: icon, kind, one-line detail, and the time.
struct EventRow: View {
    @ObservedObject var event: LogEvent
    @Environment(\.appTheme) private var theme

    @AppStorage(Prefs.volumeUnit) private var volumeUnit: VolumeUnit = Prefs.defaultVolumeUnit
    @AppStorage(Prefs.unitSystem) private var unitSystem: UnitSystem = Prefs.defaultUnitSystem

    var body: some View {
        if event.isDeleted || event.managedObjectContext == nil {
            EmptyView()
        } else {
            HStack(spacing: 12) {
                KindIcon(kind: event.kind, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(theme.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(event.startDate ?? .now, style: .time)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(theme.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
    }

    private var title: String {
        if event.kind == .bottle, let content = event.bottleContent { return Zh.bottle(content) }
        if event.kind == .diaper, let kind = event.diaperKind { return Zh.diaper(kind) }
        return Zh.kind(event.kind)
    }

    private var detail: String {
        switch event.kind {
        case .bottle:
            let amount = Zh.ml(event.amountML)
            guard let content = event.bottleContent else { return amount }
            return "\(amount) \(Zh.bottle(content))"
        case .diaper:
            return event.diaperKind.map { Zh.diaper($0) } ?? ""
        case .sleep:
            return event.isRunning ? "睡眠中" : DurationFormat.short(event.duration())
        case .breastfeed:
            var parts: [String] = []
            for side in BreastSide.allCases {
                let seconds = event.breastSeconds(side)
                if seconds > 0 { parts.append("\(Zh.side(side)) \(DurationFormat.compact(seconds))") }
            }
            if parts.isEmpty { return event.isRunning ? "计时中" : "" }
            return parts.joined(separator: " · ")
        default:
            return EventDescriber(volumeUnit: volumeUnit, unitSystem: unitSystem).summary(for: event)
        }
    }
}

#Preview {
    List {
        ForEach(PreviewData.events(limit: 4), id: \.objectID) { event in
            EventRow(event: event)
        }
    }
    .previewEnvironment()
}
