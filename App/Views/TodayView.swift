import SwiftUI
import Combine
import CoreData
import BabyLogKit

struct TodayView: View {
    @ObservedObject var baby: Baby
    let day: Date
    @Binding var link: DeepLink?

    @Environment(\.managedObjectContext) private var context
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @AppStorage(HomeLayoutStore.storageKey) private var layoutJSON = ""

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }
    @FetchRequest private var running: FetchedResults<LogEvent>
    @FetchRequest private var allEvents: FetchedResults<LogEvent>

    @State private var editor: EditorTarget?
    @State private var nursing: NursingSheetItem?
    @State private var feedChoice = false
    /// Same widget URL delivered twice (cold start plus a second open) must not stack another sheet.
    @State private var openedLinkAt: (key: String, date: Date)?
    @State private var feedback = 0
    @State private var timelineCard: HomeCard?
    @State private var kindHistory: EventKind?
    @AppStorage(AIPreferences.enabledKey) private var aiEnabled = false
    @State private var showAIDraft = false
    @State private var showHomeCards = false
    /// Relative labels refresh on a timer. The list itself is not a TimelineView:
    /// wrapping it rebuilt the whole scroll view, and the bottom section only appeared
    /// once that rebuild was already under way.
    @State private var now = Date()
    /// Bumps when the store saves, so the cards re-read the context the form just wrote.
    @State private var savedRecords = 0
    /// Rollup taken from that re-read. The list was still showing the snapshot from before the sheet closed.
    @State private var displayedCare: CareRollup?

    init(baby: Baby, day: Date, link: Binding<DeepLink?> = .constant(nil)) {
        _baby = ObservedObject(wrappedValue: baby)
        self.day = day
        _link = link
        _running = FetchRequest(fetchRequest: LogEvent.requestRunning(baby: baby))
        _allEvents = FetchRequest(fetchRequest: LogEvent.requestAll(baby: baby))
    }

    private var layout: BabyHomeLayout {
        guard let id = baby.uuid else { return BabyHomeLayout() }
        let data = layoutJSON.isEmpty ? nil : Data(layoutJSON.utf8)
        return HomeLayoutStore.load(babyID: id, from: data)
    }

    private var runningNursing: LogEvent? {
        running.first(where: { $0.kind == .breastfeed })
    }

    /// The form's own refetch already saw the new row. `FetchedResults` under a sheet can keep the previous snapshot.
    private var loggedEvents: [LogEvent] {
        _ = savedRecords
        return (try? context.fetch(LogEvent.requestAll(baby: baby))) ?? Array(allEvents)
    }

    var body: some View {
        let care = displayedCare ?? CareRollup.make(events: loggedEvents, now: now)
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
                    ForEach(layout.recordCards) { card in
                        CareCardRow(
                            card: card,
                            prominent: true,
                            detailed: layout.isDetailed(card),
                            care: care,
                            now: now,
                            onOpen: { timelineCard = card },
                            onAdd: { add(card) }
                        )
                        .id("\(card.id)-\(savedRecords)")
                        .draggable(card.rawValue)
                        .dropDestination(for: String.self) { items, _ in
                            guard let raw = items.first, let source = HomeCard(rawValue: raw) else { return false }
                            saveLayout(layout.placing(source, before: card))
                            return true
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(UICopy.t(.newPrefix, language))
                        Spacer(minLength: 8)
                        Button {
                            showHomeCards = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.body.weight(.semibold))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("home-cards-config")
                        .accessibilityLabel(language == .zh ? "配置记录" : "Choose records")
                    }
                    .textCase(nil)
                    Text(layout.recordCards.map(\.rawValue).joined(separator: ","))
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("home-card-order")
                    }
                }
                .themedSection()

                if !layout.otherCards.isEmpty || !OtherLogKinds.kinds.isEmpty {
                    Section {
                        OtherLogStrip(cards: layout.otherCards, kinds: OtherLogKinds.kinds) { card in
                            add(card)
                        } onKind: { kind in
                            editor = .new(kind)
                        } onHistory: { kind in
                            kindHistory = kind
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text(UICopy.t(.otherLog, language)).textCase(nil)
                    }
                    .themedSection()
                }

                UpNextView(baby: baby, now: now)
            }
            .themedList()
            .id(day)
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
        .navigationTitle(baby.displayName)
        .background(alignment: .topLeading) {
            SaveTraceProbe(babyID: SaveTrace.babyID(baby.uuid), contextID: SaveTrace.contextID(context))
        }
        .navigationBarTitleDisplayMode(.large)
        .systemBarChrome()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BabySwitcherMenu()
            }
            if aiEnabled, AIRuntime.access().maySend {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard AIRuntime.access().maySend else { return }
                        showAIDraft = true
                    } label: { Image(systemName: "sparkles") }
                        .accessibilityIdentifier("ai-record-draft")
                }
            }
        }
        .sheet(isPresented: $showAIDraft) {
            AIChatView(baby: baby)
        }
        .sheet(isPresented: $showHomeCards) {
            NavigationStack {
                HomeCardsSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(language == .zh ? "完成" : "Done") { showHomeCards = false }
                                .accessibilityIdentifier("home-cards-done")
                        }
                    }
            }
        }
        .sensoryFeedback(.success, trigger: feedback)
        .onChange(of: link, initial: true) { _, newLink in
            guard let newLink else { return }
            link = nil
            open(newLink)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave, object: context)) { _ in
            savedRecords += 1
        }
        .onChange(of: savedRecords) { _, _ in
            let rows = (try? context.fetch(LogEvent.requestAll(baby: baby))) ?? []
            let fresh = CareRollup.make(events: rows, now: .now)
            displayedCare = fresh
            let formula = fresh.lastFormulaML.map { String(Int($0)) } ?? "nil"
            let breast = fresh.lastBreastSeconds.map { String(Int($0)) } ?? "nil"
            SaveTrace.shared.record("todayFetch rows=\(rows.count) formula=\(formula) breast=\(breast)")
        }
        .sheet(item: $editor, onDismiss: { savedRecords += 1 }) { target in
            EventEditorView(baby: baby, target: target)
                .interactiveDismissDisabled(true)
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
        .navigationDestination(item: $kindHistory) { kind in
            KindHistoryView(baby: baby, kind: kind)
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

    private func saveLayout(_ next: BabyHomeLayout) {
        guard let id = baby.uuid else { return }
        let data = HomeLayoutStore.save(next, babyID: id, into: layoutJSON.isEmpty ? nil : Data(layoutJSON.utf8))
        layoutJSON = String(decoding: data, as: UTF8.self)
    }

    private func add(_ card: HomeCard) {
        editor = .card(card)
    }

    private func wake(_ event: LogEvent) {
        var draft = EventDraft(event: event)
        draft.endDate = .now
        draft.apply(to: event)
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

}

/// Republishes the save chain so a failed UI assertion can show baby, context, draft, and who closed the sheet.
private struct SaveTraceProbe: View {
    @ObservedObject private var trace = SaveTrace.shared
    let babyID: String
    let contextID: String

    var body: some View {
        Text(trace.summary)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityIdentifier("save-trace")
            .accessibilityLabel("\(trace.summary) todayBaby=\(babyID) todayCtx=\(contextID)")
    }
}

#Preview {
    NavigationStack {
        TodayView(baby: PreviewData.baby, day: Calendar.current.startOfDay(for: .now))
    }
    .previewEnvironment()
}
