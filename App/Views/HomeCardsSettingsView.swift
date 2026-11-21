import SwiftUI
import CoreData
import BabyLogKit

/// Which cards Today shows, per baby. A feed preference only fills the suggestion.
/// A card that already has records stays on Today even if it is not in the suggestion.
struct HomeCardsSettingsView: View {
    @FetchRequest(fetchRequest: Baby.lblAllByCreation()) private var babies: FetchedResults<Baby>
    @AppStorage(Prefs.selectedBabyID) private var selectedBabyID = ""
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @AppStorage(HomeLayoutStore.storageKey) private var layoutJSON = ""
    @Environment(\.managedObjectContext) private var context

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    private var baby: Baby? {
        babies.first { $0.uuid?.uuidString == selectedBabyID } ?? babies.first
    }

    var body: some View {
        Form {
            if let baby, let id = baby.uuid {
                editor(baby, id: id)
            }
        }
        .themedList()
        .navigationTitle(Copy.homeCards(language))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func editor(_ baby: Baby, id: UUID) -> some View {
        let recorded = recordedCards(baby)
        let layout = HomeLayoutStore.load(babyID: id, from: layoutData)
        Section {
            Picker(Copy.feedStyle(language), selection: preference(id, layout)) {
                        ForEach(FeedPreference.allCases) { item in
                            Text(Copy.preference(item, language)).tag(item)
                        }
                    }
                } footer: {
                    Text(Copy.feedStyleFootnote(language))
                }
                .themedSection()

                Section {
                    ForEach(HomeCard.allCases) { card in
                        Toggle(Copy.card(card, language), isOn: visible(id, layout, card, recorded: recorded))
                            .disabled(recorded.contains(card))
                    }
                } header: {
                    Text(Copy.homeCards(language))
                }
                .themedSection()

                Section {
                    ForEach(layout.resolved(recorded: recorded)) { card in
                        HStack {
                            Text(Copy.card(card, language))
                            Spacer()
                            Button {
                                reorder(card, up: true, layout: layout, recorded: recorded, id: id)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .accessibilityLabel(language == .zh ? "上移\(Copy.card(card, language))" : "Move \(Copy.card(card, language)) up")
                            Button {
                                reorder(card, up: false, layout: layout, recorded: recorded, id: id)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .accessibilityLabel(language == .zh ? "下移\(Copy.card(card, language))" : "Move \(Copy.card(card, language)) down")
                        }
                    }
                } header: {
                    Text(language == .zh ? "首页顺序" : "Home order")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(language == .zh ? "今天页的摘要和卡片按这个顺序排。" : "Today's summary and cards use this order.")
                        Text(Copy.widgetSeparate(language))
                    }
                }
                .themedSection()
    }

    private func reorder(_ card: HomeCard, up: Bool, layout: BabyHomeLayout, recorded: Set<HomeCard>, id: UUID) {
        var cards = layout.resolved(recorded: recorded)
        guard let index = cards.firstIndex(of: card) else { return }
        let next = up ? index - 1 : index + 1
        guard cards.indices.contains(next) else { return }
        cards.swapAt(index, next)
        var copy = layout
        copy.cards = cards
        write(copy, id)
    }

    private var layoutData: Data? {
        layoutJSON.isEmpty ? nil : Data(layoutJSON.utf8)
    }

    private func recordedCards(_ baby: Baby) -> Set<HomeCard> {
        let request = LogEvent.requestAll(baby: baby)
        let events = (try? context.fetch(request)) ?? []
        return HomeCardMatch.recordedCards(in: events)
    }

    private func preference(_ id: UUID, _ layout: BabyHomeLayout) -> Binding<FeedPreference> {
        Binding(
            get: { layout.preference },
            set: { newValue in
                var next = layout
                next.preference = newValue
                next.cards = newValue.suggestedCards
                write(next, id)
            }
        )
    }

    private func visible(_ id: UUID, _ layout: BabyHomeLayout, _ card: HomeCard, recorded: Set<HomeCard>) -> Binding<Bool> {
        Binding(
            get: { layout.cards.contains(card) || recorded.contains(card) },
            set: { write(layout.setting(card, visible: $0), id) }
        )
    }

    private func write(_ layout: BabyHomeLayout, _ id: UUID) {
        let data = HomeLayoutStore.save(layout, babyID: id, into: layoutData)
        layoutJSON = String(data: data, encoding: .utf8) ?? layoutJSON
    }
}
