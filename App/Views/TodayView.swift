import SwiftUI
import UIKit
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
                        ReorderableRecordCard(
                            card: card,
                            detailed: layout.isDetailed(card),
                            care: care,
                            now: now,
                            savedRecords: savedRecords,
                            siblings: layout.recordCards,
                            onOpen: { timelineCard = card },
                            onAdd: { add(card) },
                            move: { source, target in
                                saveLayout(layout.placing(source, before: target))
                            }
                        )
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

private struct ReorderableRecordCard: View {
    let card: HomeCard
    let detailed: Bool
    let care: CareRollup
    let now: Date
    let savedRecords: Int
    let siblings: [HomeCard]
    let onOpen: () -> Void
    let onAdd: () -> Void
    let move: (HomeCard, HomeCard) -> Void

    var body: some View {
        CareCardRow(
            card: card,
            prominent: true,
            detailed: detailed,
            care: care,
            now: now,
            onOpen: onOpen,
            onAdd: onAdd
        )
        .id("\(card.id)-\(savedRecords)")
        .background {
            CardReorderInstaller(card: card, siblings: siblings, move: move)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .listRowBackground(Color.clear)
    }
}

/// Sees the long-press drag from the window, because a row-level drag never receives the XCTest touch.
private final class WindowReorder: NSObject, UIGestureRecognizerDelegate {
    static let shared = WindowReorder()
    var siblings: [HomeCard] = []
    var move: (HomeCard, HomeCard) -> Void = { _, _ in }
    var frames: [HomeCard: CGRect] = [:]
    private var installed: Set<ObjectIdentifier> = []
    private var source: HomeCard?
    private var start = CGPoint.zero
    private var last = CGPoint.zero
    private var scroll: UIScrollView?
    private var scrollWasEnabled = true

    func install(on window: UIWindow) {
        let key = ObjectIdentifier(window)
        guard installed.insert(key).inserted else { return }
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handle(_:)))
        press.minimumPressDuration = 0.45
        press.allowableMovement = 80
        press.cancelsTouchesInView = false
        press.delegate = self
        window.addGestureRecognizer(press)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func handle(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: nil)
        if point != .zero { last = point }
        let window = gesture.view as? UIWindow
        switch gesture.state {
        case .began:
            start = point == .zero ? last : point
            source = card(at: start, in: window)
            holdScroll(at: start, in: window)
        case .ended, .cancelled:
            let drop = point == .zero ? last : point
            commit(drop: drop, in: window)
            releaseScroll()
        case .failed:
            source = nil
        default:
            break
        }
    }

    private func commit(drop: CGPoint, in window: UIWindow?) {
        guard let source else { return }
        let movedUp = drop.y < start.y - 24
        let movedDown = drop.y > start.y + 24
        let target = card(at: drop, in: window) ?? ((movedUp || movedDown) ? neighbor(of: source, movingUp: movedUp) : nil)
        self.source = nil
        if let target, target != source {
            move(source, target)
        }
    }

    private func holdScroll(at point: CGPoint, in window: UIWindow?) {
        guard let window, scroll == nil else { return }
        var view = window.hitTest(point, with: nil)
        while let current = view {
            if let scroller = current as? UIScrollView {
                scrollWasEnabled = scroller.isScrollEnabled
                scroller.isScrollEnabled = false
                scroll = scroller
                return
            }
            view = current.superview
        }
    }

    private func releaseScroll() {
        scroll?.isScrollEnabled = scrollWasEnabled
        scroll = nil
    }

    private func neighbor(of card: HomeCard, movingUp: Bool) -> HomeCard? {
        guard let index = siblings.firstIndex(of: card) else { return nil }
        let next = movingUp ? index - 1 : index + 1
        guard siblings.indices.contains(next) else { return nil }
        return siblings[next]
    }

    /// The card under the finger: our row frame first, then a summary button in the window.
    private func card(at point: CGPoint, in window: UIWindow?) -> HomeCard? {
        let hits = frames.filter { item in
            let frame = item.value
            return frame.width > 8 && frame.height > 8 && frame.contains(point)
        }
        if let nearest = hits.min(by: { $0.value.width * $0.value.height < $1.value.width * $1.value.height }) {
            return nearest.key
        }
        guard let window else { return nil }
        var found: (HomeCard, CGFloat)?
        func walk(_ view: UIView) {
            if let card = HomeCard.card(forSummaryID: view.accessibilityIdentifier) {
                let frame = view.convert(view.bounds, to: nil)
                if frame.width > 8, frame.height > 8, frame.contains(point) {
                    let area = frame.width * frame.height
                    if found == nil || area < found!.1 {
                        found = (card, area)
                    }
                }
            }
            for child in view.subviews {
                walk(child)
            }
        }
        walk(window)
        return found?.0
    }
}

private extension HomeCard {
    static func card(forSummaryID identifier: String?) -> HomeCard? {
        switch identifier {
        case "summary-breast": return .breast
        case "summary-formula": return .formula
        case "summary-wet": return .wet
        case "summary-dirty": return .dirty
        case "summary-change": return .diaperChange
        case "summary-sleep": return .sleep
        default: return nil
        }
    }
}

private struct CardReorderInstaller: UIViewRepresentable {
    let card: HomeCard
    let siblings: [HomeCard]
    let move: (HomeCard, HomeCard) -> Void

    func makeUIView(context: Context) -> ReorderInstallView {
        let view = ReorderInstallView()
        view.card = card
        return view
    }

    func updateUIView(_ uiView: ReorderInstallView, context: Context) {
        uiView.card = card
        uiView.siblings = siblings
        uiView.move = move
        uiView.publish()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ReorderInstallView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

private final class ReorderInstallView: UIView {
    var card: HomeCard = .sleep
    var siblings: [HomeCard] = []
    var move: (HomeCard, HomeCard) -> Void = { _, _ in }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        publish()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        publish()
    }

    func publish() {
        WindowReorder.shared.siblings = siblings
        WindowReorder.shared.move = move
        if window == nil {
            WindowReorder.shared.frames[card] = nil
            return
        }
        let host: UIView?
        if bounds.height > 8 {
            host = self
        } else if let parent = superview, parent.bounds.height > 40, parent.bounds.height < 240 {
            host = parent
        } else {
            host = nil
        }
        if let host, host.bounds.width > 8 {
            WindowReorder.shared.frames[card] = host.convert(host.bounds, to: nil)
        }
        guard let window else { return }
        WindowReorder.shared.install(on: window)
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
