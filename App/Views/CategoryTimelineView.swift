import SwiftUI
import CoreData
import BabyLogKit

/// One category's records. Filters use the phone's calendar, so a late-night entry stays on that local day.
struct CategoryTimelineView: View {
    @ObservedObject var baby: Baby
    let card: HomeCard

    @Environment(\.managedObjectContext) private var context
    @Environment(\.appTheme) private var theme
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @FetchRequest private var events: FetchedResults<LogEvent>

    @State private var range: TimelineChoice = .today
    @State private var pickedDay = Date()
    @State private var editor: EditorTarget?

    init(baby: Baby, card: HomeCard) {
        self.baby = baby
        self.card = card
        _events = FetchRequest(fetchRequest: LogEvent.requestAll(baby: baby))
    }

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    private var window: TimelineRange {
        switch range {
        case .today: return .today
        case .yesterday: return .yesterday
        case .last7: return .last7Days
        case .all: return .all
        case .pick: return .day(pickedDay)
        }
    }

    private var rows: [LogEvent] {
        let calendar = Calendar.current
        let now = Date()
        return events.filter { event in
            guard HomeCardMatch.matches(event, card: card), let start = event.startDate else { return false }
            return window.contains(start, now: now, calendar: calendar)
        }
    }

    var body: some View {
        List {
            Section {
                Picker(Copy.today(language), selection: $range) {
                    Text(Copy.today(language)).tag(TimelineChoice.today)
                    Text(Copy.yesterday(language)).tag(TimelineChoice.yesterday)
                    Text(Copy.last7(language)).tag(TimelineChoice.last7)
                    Text(Copy.all(language)).tag(TimelineChoice.all)
                    Text(Copy.pickDate(language)).tag(TimelineChoice.pick)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                if range == .pick {
                    DatePicker(Copy.pickDate(language), selection: $pickedDay, displayedComponents: .date)
                }
                Text(totalLine)
                    .font(.headline)
                    .accessibilityIdentifier("timeline-total")
            }
            .themedSection()

            if rows.isEmpty {
                Section {
                    Text(Copy.noRecords(language))
                        .foregroundStyle(theme.secondary)
                        .accessibilityIdentifier("timeline-empty")
                }
                .themedSection()
            } else {
                Section {
                    ForEach(rows, id: \.objectID) { event in
                        Button {
                            editor = .edit(event)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(timeLine(event))
                                Text(detail(event))
                                    .font(.subheadline)
                                    .foregroundStyle(theme.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                }
                .themedSection()
            }
        }
        .themedList()
        .navigationTitle(Copy.card(card, language))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editor) { target in
            EventEditorView(baby: baby, target: target)
        }
    }

    private var totalLine: String {
        let count = rows.count
        switch card {
        case .formula:
            let ml = rows.reduce(0) { $0 + $1.amountML }
            return "\(Copy.count(count, language)) · \(Copy.ml(ml, language))"
        case .breast:
            let seconds = rows.reduce(0) { $0 + $1.totalBreastSeconds(at: $1.endDate ?? .now) }
            return "\(Copy.count(count, language)) · \(Copy.duration(seconds, language))"
        default:
            return Copy.count(count, language)
        }
    }

    private func timeLine(_ event: LogEvent) -> String {
        let start = event.startDate ?? .now
        let clock = start.formatted(date: .abbreviated, time: .shortened)
        if let end = event.endDate, event.kind.hasDuration {
            return "\(clock) – \(end.formatted(date: .omitted, time: .shortened))"
        }
        return clock
    }

    private func detail(_ event: LogEvent) -> String {
        switch card {
        case .formula:
            return Copy.ml(event.amountML, language)
        case .breast:
            return Copy.duration(event.totalBreastSeconds(at: event.endDate ?? .now), language)
        case .wet, .dirty, .diaperChange:
            return event.diaperKind.map { Zh.diaper($0) } ?? ""
        case .sleep:
            guard let start = event.startDate, let end = event.endDate else { return Copy.sleeping(language) }
            return Copy.duration(end.timeIntervalSince(start), language)
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            context.delete(rows[index])
        }
        context.saveIfNeeded()
    }
}

private enum TimelineChoice: Hashable {
    case today, yesterday, last7, all, pick
}
