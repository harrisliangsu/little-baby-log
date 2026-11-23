import SwiftUI
import BabyLogKit

/// One line in a timeline: icon, kind, one-line detail, and the time.
struct EventRow: View {
    @ObservedObject var event: LogEvent
    @Environment(\.appTheme) private var theme
    @Environment(\.uiLanguage) private var language

    @AppStorage(Prefs.volumeUnit) private var volumeUnit: VolumeUnit = Prefs.defaultVolumeUnit
    @AppStorage(Prefs.unitSystem) private var unitSystem: UnitSystem = Prefs.defaultUnitSystem

    var body: some View {
        if event.isDeleted || event.managedObjectContext == nil {
            EmptyView()
        } else {
            HStack(spacing: 12) {
                KindIcon(kind: event.kind, diaper: event.diaperKind, size: 40)
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
        if event.kind == .bottle, let content = event.bottleContent { return UICopy.bottle(content, language) }
        if event.kind == .diaper, let kind = event.diaperKind { return UICopy.diaper(kind, language) }
        return UICopy.kind(event.kind, language)
    }

    private var detail: String {
        EventDescriber(volumeUnit: volumeUnit, unitSystem: unitSystem).summary(for: event, language: language)
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
