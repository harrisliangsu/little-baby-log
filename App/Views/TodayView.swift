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
                            onOpen: { timelineCard = card },
                            onAdd: { add(card) },
                            moveBefore: { source in
                                saveLayout(layout.placing(source, before: card))
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
    let onOpen: () -> Void
    let onAdd: () -> Void
    let moveBefore: (HomeCard) -> Void

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
            CardReorderMarker(card: card, moveBefore: moveBefore)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .listRowBackground(Color.clear)
    }
}

/// Long-press drag that writes the new order itself.
/// SwiftUI's drag-and-drop session never receives the XCTest press-and-drag, so the drop callback never ran.
private enum CardReorder {
    static var markers: [HomeCard: WeakCardView] = [:]

    static func destination(from source: HomeCard, point: CGPoint) -> HomeCard? {
        let frames: [(HomeCard, CGRect)] = markers.compactMap { card, box in
            guard let view = box.view, view.window != nil else { return nil }
            let frame = view.convert(view.bounds, to: nil)
            guard frame.width > 8, frame.height > 8 else { return nil }
            return (card, frame)
        }
        if let hit = frames.first(where: { $0.0 != source && $0.1.contains(point) }) {
            return hit.0
        }
        if let below = frames
            .filter({ $0.0 != source && $0.1.minY >= point.y - 12 })
            .min(by: { $0.1.minY < $1.1.minY }) {
            return below.0
        }
        return frames
            .filter { $0.0 != source && $0.1.maxY <= point.y + 12 }
            .max(by: { $0.1.maxY < $1.1.maxY })?.0
    }

    static func frame(of card: HomeCard) -> CGRect? {
        guard let view = markers[card]?.view, view.window != nil else { return nil }
        let frame = view.convert(view.bounds, to: nil)
        guard frame.width > 8, frame.height > 8 else { return nil }
        return frame
    }

    /// The card directly above `card`, so an upward drag still changes the order when the finger misses.
    static func cardAbove(_ card: HomeCard) -> HomeCard? {
        guard let source = frame(of: card) else { return nil }
        return markers.compactMap { other, box -> (HomeCard, CGRect)? in
            guard other != card, let view = box.view, view.window != nil else { return nil }
            let frame = view.convert(view.bounds, to: nil)
            guard frame.maxY <= source.minY + 12 else { return nil }
            return (other, frame)
        }
        .max(by: { $0.1.maxY < $1.1.maxY })?.0
    }
}

private final class WeakCardView {
    weak var view: UIView?
    init(_ view: UIView) { self.view = view }
}

private struct CardReorderMarker: UIViewRepresentable {
    let card: HomeCard
    let moveBefore: (HomeCard) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(moveBefore: moveBefore)
    }

    func makeUIView(context: Context) -> CardMarkerView {
        let view = CardMarkerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: CardMarkerView, context: Context) {
        uiView.card = card
        context.coordinator.card = card
        context.coordinator.moveBefore = moveBefore
        uiView.installIfNeeded()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var card: HomeCard
        var moveBefore: (HomeCard) -> Void
        var scrollView: UIScrollView?
        var scrollWasEnabled = true
        var lastPoint: CGPoint = .zero
        lazy var press: UILongPressGestureRecognizer = {
            let press = UILongPressGestureRecognizer(target: self, action: #selector(handle(_:)))
            press.minimumPressDuration = 0.6
            press.allowableMovement = 28
            press.cancelsTouchesInView = true
            press.delegate = self
            return press
        }()

        init(moveBefore: @escaping (HomeCard) -> Void) {
            self.card = .sleep
            self.moveBefore = moveBefore
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc func handle(_ gesture: UILongPressGestureRecognizer) {
            let point = gesture.location(in: nil)
            if point != .zero { lastPoint = point }
            switch gesture.state {
            case .began:
                lockScroll(under: gesture.view)
            case .ended:
                let drop = point == .zero ? lastPoint : point
                unlockScroll()
                if let target = CardReorder.destination(from: card, point: drop) {
                    moveBefore(target)
                } else if let above = CardReorder.cardAbove(card),
                          drop.y < (CardReorder.frame(of: card)?.midY ?? .greatestFiniteMagnitude) {
                    moveBefore(above)
                }
            case .cancelled, .failed:
                unlockScroll()
            default:
                break
            }
        }

        private func lockScroll(under start: UIView?) {
            var current = start
            while let view = current {
                if let scroll = view as? UIScrollView {
                    scrollWasEnabled = scroll.isScrollEnabled
                    scroll.isScrollEnabled = false
                    scrollView = scroll
                    return
                }
                current = view.superview
            }
        }

        private func unlockScroll() {
            scrollView?.isScrollEnabled = scrollWasEnabled
            scrollView = nil
        }
    }
}

private final class CardMarkerView: UIView {
    var card: HomeCard? {
        didSet { publish() }
    }
    weak var coordinator: CardReorderMarker.Coordinator?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil, let press = coordinator?.press {
            press.view?.removeGestureRecognizer(press)
        }
        publish()
        installIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        publish()
        installIfNeeded()
    }

    func publish() {
        guard let card else { return }
        if window == nil {
            if CardReorder.markers[card]?.view === self {
                CardReorder.markers[card] = nil
            }
        } else {
            CardReorder.markers[card] = WeakCardView(self)
        }
    }

    func installIfNeeded() {
        guard window != nil, bounds.height > 40, let coordinator else { return }
        var host: UIView = self
        while let parent = host.superview, !(parent is UIScrollView),
              parent.bounds.height < host.bounds.height + 80 {
            host = parent
        }
        guard host !== self, !(host is UIScrollView) else { return }
        if host.gestureRecognizers?.contains(where: { $0 === coordinator.press }) != true {
            host.addGestureRecognizer(coordinator.press)
        }
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
