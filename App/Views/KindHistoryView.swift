import SwiftUI
import CoreData
import BabyLogKit

/// History for a kind that is not one of the home cards. Each row opens the same editor.
struct KindHistoryView: View {
    @ObservedObject var baby: Baby
    let kind: EventKind

    @Environment(\.managedObjectContext) private var context
    @FetchRequest private var events: FetchedResults<LogEvent>
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @State private var editor: EditorTarget?
    @State private var pendingDelete: LogEvent?

    init(baby: Baby, kind: EventKind) {
        self.baby = baby
        self.kind = kind
        _events = FetchRequest(fetchRequest: LogEvent.requestAll(baby: baby, kinds: [kind]))
    }

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    var body: some View {
        List {
            ForEach(events, id: \.objectID) { event in
                Button {
                    editor = .edit(event)
                } label: {
                    EventRow(event: event)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("history-entry")
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(language == .zh ? "删除" : "Delete", role: .destructive) {
                        pendingDelete = event
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button(language == .zh ? "编辑" : "Edit") { editor = .edit(event) }
                }
            }
        }
        .themedList()
        .navigationTitle(UICopy.kind(kind, language))
        .sheet(item: $editor) { target in
            EventEditorView(baby: baby, target: target)
        }
        .confirmationDialog(
            language == .zh ? "删除这条记录？" : "Delete this record?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(language == .zh ? "删除" : "Delete", role: .destructive) {
                if let event = pendingDelete {
                    WetDiaperLink.deleteLinked(to: event, in: context)
                    context.delete(event)
                    context.saveIfNeeded()
                }
                pendingDelete = nil
            }
            Button(language == .zh ? "取消" : "Cancel", role: .cancel) { pendingDelete = nil }
        }
    }
}
