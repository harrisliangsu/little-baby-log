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
                        WetDiaperLink.deleteLinked(to: event, in: context)
                        context.delete(event)
                        context.saveIfNeeded()
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
    }
}
