import SwiftUI
import CoreData
import BabyLogKit

/// How the History tab shows the log: the hour-by-hour recap of a day, or the full list.
enum HistoryMode: String, CaseIterable, Identifiable {
    case recap, list

    var id: String { rawValue }

    func title(_ language: ResolvedLanguage) -> String {
        switch self {
        case .recap: return UICopy.t(.recap, language)
        case .list: return UICopy.t(.list, language)
        }
    }
}

/// The History tab: a "Recap | List" switch (remembered) over the daily recap or the list of every entry.
struct HistoryView: View {
    let baby: Baby

    @AppStorage(Prefs.historyMode) private var mode: HistoryMode = .recap
    @Environment(\.uiLanguage) private var language

    var body: some View {
        Group {
            switch mode {
            case .recap:
                DayRecapView(baby: baby, embedded: true)
            case .list:
                HistoryListView(baby: baby)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker(UICopy.t(.filter, language), selection: $mode) {
                ForEach(HistoryMode.allCases) { mode in
                    Text(mode.title(language)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlChrome()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .navigationTitle(UICopy.t(.history, language))
        .systemBarChrome()
        .navigationBarTitleDisplayMode(mode == .recap ? .inline : .large)
    }
}

/// Every entry, grouped by day, newest first.
private struct HistoryListView: View {
    let baby: Baby

    @FetchRequest private var events: FetchedResults<LogEvent>
    @Environment(\.managedObjectContext) private var context
    @Environment(\.appTheme) private var theme
    @State private var filter: EventKind?
    @State private var editor: EditorTarget?
    @State private var nursing: NursingSheetItem?

    init(baby: Baby) {
        self.baby = baby
        _events = FetchRequest(fetchRequest: LogEvent.requestAll(baby: baby))
    }

    private struct DayGroup: Identifiable {
        let day: Date
        /// Events shown under this day (after the kind filter).
        let rows: [LogEvent]
        /// Unfiltered events of this day and the day before, for the summary line.
        let summaryEvents: [LogEvent]
        var id: Date { day }
    }

    private func makeGroups() -> [DayGroup] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: Array(events)) { (event: LogEvent) -> Date in
            calendar.startOfDay(for: event.startDate ?? .distantPast)
        }
        var groups: [DayGroup] = []
        for day in byDay.keys.sorted(by: >) {
            let all = byDay[day] ?? []
            let rows = filter == nil ? all : all.filter { $0.kind == filter }
            if rows.isEmpty { continue }
            let previousDay = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            let summaryEvents = all + (byDay[previousDay] ?? [])
            groups.append(DayGroup(day: day, rows: rows, summaryEvents: summaryEvents))
        }
        return groups
    }

    var body: some View {
        let groups = makeGroups()
        List {
            if groups.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "clock")
                } description: {
                    Text(emptyMessage)
                }
                .listRowBackground(Color.clear)
                .foregroundStyle(theme.secondary)
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.rows, id: \.objectID) { event in
                        Button {
                            open(event)
                        } label: {
                            EventRow(event: event)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(event)
                            } label: {
                                Label(UICopy.t(.delete, language), systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    DayHeader(day: group.day, events: group.summaryEvents)
                }
                .themedSection()
            }
        }
        .themedList()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                filterMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                addMenu
            }
        }
        .sheet(item: $editor) { target in
            EventEditorView(baby: baby, target: target)
        }
        .sheet(item: $nursing) { item in
            BreastTimerView(event: item.event, suggestedSide: item.suggestedSide)
        }
    }

    @Environment(\.uiLanguage) private var language

    private var emptyTitle: String {
        filter == nil ? UICopy.t(.noEntries, language) : UICopy.t(.nothingHere, language)
    }

    private var emptyMessage: String {
        if let filter {
            return UICopy.kind(filter, language)
        }
        return ""
    }

    private var filterMenu: some View {
        Menu {
            Picker(UICopy.t(.filter, language), selection: $filter) {
                Text(UICopy.t(.everything, language)).tag(EventKind?.none)
                ForEach(EventKind.allCases) { kind in
                    Text(UICopy.kind(kind, language)).tag(Optional(kind))
                }
            }
        } label: {
            Image(systemName: filter == nil
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel(UICopy.t(.filter, language))
    }

    private var addMenu: some View {
        Menu {
            ForEach(EventKind.allCases) { kind in
                Button {
                    editor = .new(kind)
                } label: {
                    Label(UICopy.kind(kind, language), systemImage: kind.symbolName)
                }
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel(language == .zh ? "补记一条" : "Log a past entry")
    }

    private func open(_ event: LogEvent) {
        if event.kind == .breastfeed && event.isRunning {
            nursing = NursingSheetItem(event: event, suggestedSide: nil)
        } else {
            editor = .edit(event)
        }
    }

    private func delete(_ event: LogEvent) {
        context.delete(event)
        context.saveIfNeeded()
    }
}

private struct DayHeader: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.uiLanguage) private var language

    let day: Date
    let events: [LogEvent]
    @AppStorage(Prefs.volumeUnit) private var volumeUnit: VolumeUnit = Prefs.defaultVolumeUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.primary)
            Text(summaryLine)
                .font(.footnote)
                .foregroundStyle(theme.secondary)
        }
        .textCase(nil)
        .padding(.top, 6)
    }

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return Copy.today(language) }
        if calendar.isDateInYesterday(day) { return Copy.yesterday(language) }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var summaryLine: String {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        let summary = DaySummary(events: events, interval: DateInterval(start: day, end: end))
        var parts: [String] = []
        if summary.sleep > 0 {
            parts.append((language == .zh ? "睡眠 " : "Sleep ") + DurationFormat.short(summary.sleep))
        }
        if summary.feedCount > 0 {
            parts.append(language == .zh ? "\(summary.feedCount)次喂奶" : (summary.feedCount == 1 ? "1 feed" : "\(summary.feedCount) feeds"))
        }
        if summary.diaperCount > 0 {
            parts.append(language == .zh ? "\(summary.diaperCount)次尿布" : (summary.diaperCount == 1 ? "1 diaper" : "\(summary.diaperCount) diapers"))
        }
        if summary.pumpML > 0 {
            parts.append(volumeUnit.format(milliliters: summary.pumpML) + (language == .zh ? " 吸奶" : " pumped"))
        }
        return parts.isEmpty ? (language == .zh ? "没有睡眠、喂奶或尿布" : "No sleep, feeds or diapers") : parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        HistoryView(baby: PreviewData.baby)
    }
    .previewEnvironment()
}
