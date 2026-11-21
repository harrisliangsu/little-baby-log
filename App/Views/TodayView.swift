import SwiftUI
import CoreData
import BabyLogKit

struct TodayView: View {
    @ObservedObject var baby: Baby
    let day: Date
    @Binding var link: DeepLink?

    @Environment(\.managedObjectContext) private var context
    @Environment(\.appTheme) private var theme
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }
    @FetchRequest private var running: FetchedResults<LogEvent>
    @FetchRequest private var dayEvents: FetchedResults<LogEvent>

    @State private var editor: EditorTarget?
    @State private var nursing: NursingSheetItem?
    @State private var feedChoice = false
    /// Same widget URL delivered twice (cold start plus a second open) must not stack another sheet.
    @State private var openedLinkAt: (key: String, date: Date)?
    @State private var feedback = 0
    @State private var showWidgetPreview = false
    @State private var timelineCard: HomeCard?

    init(baby: Baby, day: Date, link: Binding<DeepLink?> = .constant(nil)) {
        _baby = ObservedObject(wrappedValue: baby)
        self.day = day
        _link = link
        _running = FetchRequest(fetchRequest: LogEvent.requestRunning(baby: baby))
        _dayEvents = FetchRequest(fetchRequest: LogEvent.requestOverlapping(baby: baby, from: day))
    }

    private var runningSleep: LogEvent? {
        running.first(where: { $0.kind == .sleep })
    }

    private var runningNursing: LogEvent? {
        running.first(where: { $0.kind == .breastfeed })
    }

    private var timeline: [LogEvent] {
        dayEvents.filter { !$0.isRunning }
    }

    var body: some View {
        List {
            if !running.isEmpty {
                Section {
                    ForEach(running, id: \.objectID) { event in
                        ActiveTimerRow(
                            event: event,
                            onWake: { wake(event) },
                            onOpen: { openNursing(event) }
                        )
                    }
                }
                .themedSection()
            }

            Section {
                CareCardsView(baby: baby, onOpen: { timelineCard = $0 }, onAdd: { add($0) })
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(Color.clear)
            } header: {
                Text(UICopy.t(.newPrefix, language)).textCase(nil)
            }
            .themedSection()

            UpNextView(baby: baby)

            Section {
                QuickActionsGrid(
                    isSleeping: runningSleep != nil,
                    onTap: { quickTap($0) },
                    onLogPast: { editor = .new($0) },
                    onQuickDiaper: { quickDiaper($0) }
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8))
            } header: {
                Text(UICopy.t(.otherLog, language)).textCase(nil)
            }
            .themedSection()

            Section {
                NavigationLink {
                    DayRecapView(baby: baby, day: day)
                } label: {
                    Label(UICopy.t(.recapTitle, language), systemImage: "clock.arrow.circlepath")
                }
            }
            .themedSection()

            Section {
                if timeline.isEmpty {
                    Text(UICopy.t(.nothingToday, language))
                        .foregroundStyle(theme.secondary)
                } else {
                    ForEach(timeline, id: \.objectID) { event in
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
                                Label(UICopy.t(.deleteEntry, language), systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text(UICopy.t(.timeline, language)).textCase(nil)
            }
            .themedSection()
        }
        .themedList()
        .navigationTitle(baby.displayName)
        .navigationBarTitleDisplayMode(.large)
        .systemBarChrome()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showWidgetPreview = true
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .accessibilityIdentifier("show-widget-preview")
                .accessibilityLabel(language == .zh ? "小组件" : "Widget")
            }
            ToolbarItem(placement: .topBarTrailing) {
                BabySwitcherMenu()
            }
        }
        .sheet(isPresented: $showWidgetPreview) {
            WidgetPreviewSheet()
        }
        .sensoryFeedback(.success, trigger: feedback)
        .onChange(of: link, initial: true) { _, newLink in
            guard let newLink else { return }
            link = nil
            open(newLink)
        }
        .sheet(item: $editor) { target in
            EventEditorView(baby: baby, target: target)
        }
        .sheet(isPresented: $feedChoice) {
            FeedingMethodSheet(babyName: baby.displayName) { card in
                feedChoice = false
                DispatchQueue.main.async { editor = .card(card) }
            }
        }
        .sheet(item: $nursing) { item in
            BreastTimerView(event: item.event, suggestedSide: item.suggestedSide)
        }
        .navigationDestination(item: $timelineCard) { card in
            CategoryTimelineView(baby: baby, card: card)
        }
    }

    // MARK: Actions

    /// `littlebabylog://` links from widgets: the editor for a kind, or the nursing timer.
    private func open(_ link: DeepLink) {
        if let kind = StartRouting.composer(for: link) {
            let key = link.url.absoluteString
            if let opened = openedLinkAt, opened.key == key, Date().timeIntervalSince(opened.date) < 1.5 {
                return
            }
            openedLinkAt = (key, .now)
            presentComposer(kind)
            return
        }
        let present: () -> Void
        switch link {
        case .today:
            return
        case .start:
            return
        case .timeline(let card, _):
            present = { timelineCard = card }
        case .nursing, .log(.breastfeed, _):
            present = { startNursing() }
        case .log(let kind, _):
            present = { editor = .new(kind) }
        }
        if editor != nil || nursing != nil {
            // Replace whatever sheet is up; SwiftUI can't swap one sheet for another in a single update.
            editor = nil
            nursing = nil
            DispatchQueue.main.async(execute: present)
        } else {
            present()
        }
    }

    private func presentComposer(_ kind: WidgetComposerKind) {
        let present: () -> Void = {
            switch kind {
            case .feedingChoice:
                feedChoice = true
            case .editor(let card):
                editor = .card(card)
            }
        }
        if editor != nil || feedChoice || nursing != nil {
            editor = nil
            feedChoice = false
            nursing = nil
            DispatchQueue.main.async(execute: present)
        } else {
            present()
        }
    }

    private func add(_ card: HomeCard) {
        switch card {
        case .breast: startNursing()
        case .formula: editor = .new(.bottle)
        case .wet: quickDiaper(.wet)
        case .dirty: quickDiaper(.dirty)
        case .diaperChange: quickDiaper(.dry)
        case .sleep: toggleSleep()
        }
    }

    private func quickTap(_ kind: EventKind) {
        switch kind {
        case .sleep:
            toggleSleep()
        case .breastfeed:
            startNursing()
        default:
            editor = .new(kind)
        }
    }

    private func toggleSleep() {
        if let sleep = runningSleep {
            wake(sleep)
        } else {
            _ = LogEvent.create(kind: .sleep, for: baby, in: context)
            context.saveIfNeeded()
            feedback += 1
        }
    }

    private func wake(_ event: LogEvent) {
        var draft = EventDraft(event: event)
        draft.endDate = .now
        draft.apply(to: event)
        context.saveIfNeeded()
        feedback += 1
    }

    private func quickDiaper(_ kind: DiaperKind) {
        let event = LogEvent.create(kind: .diaper, for: baby, in: context)
        event.diaperKind = kind
        context.saveIfNeeded()
        feedback += 1
    }

    private func nextSide() -> BreastSide? {
        let request = LogEvent.requestLatest(baby: baby, kinds: [.breastfeed], finishedOnly: true)
        let latest = (try? context.fetch(request))?.first
        return latest?.lastSide?.other
    }

    private func startNursing() {
        if let existing = runningNursing {
            openNursing(existing)
            return
        }
        let suggestion = nextSide()
        let event = LogEvent.create(kind: .breastfeed, for: baby, in: context)
        context.saveIfNeeded()
        nursing = NursingSheetItem(event: event, suggestedSide: suggestion)
    }

    private func openNursing(_ event: LogEvent) {
        nursing = NursingSheetItem(event: event, suggestedSide: nextSide())
    }

    private func open(_ event: LogEvent) {
        if event.kind == .breastfeed && event.isRunning {
            openNursing(event)
        } else {
            editor = .edit(event)
        }
    }

    private func delete(_ event: LogEvent) {
        context.delete(event)
        context.saveIfNeeded()
    }
}

#Preview {
    NavigationStack {
        TodayView(baby: PreviewData.baby, day: Calendar.current.startOfDay(for: .now))
    }
    .previewEnvironment()
}
