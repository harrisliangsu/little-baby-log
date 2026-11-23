import SwiftUI
import CoreData
import BabyLogKit

/// Which functions sit in the log area. Cards in that list are the large shortcuts.
/// Functions left out stay on Today as smaller rows, even when they already have records.
struct HomeCardsSettingsView: View {
    @FetchRequest(fetchRequest: Baby.lblAllByCreation()) private var babies: FetchedResults<Baby>
    @AppStorage(Prefs.selectedBabyID) private var selectedBabyID = ""
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @AppStorage(HomeLayoutStore.storageKey) private var layoutJSON = ""

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
        let layout = HomeLayoutStore.load(babyID: id, from: layoutData)
        Section {
            Picker(Copy.feedStyle(language), selection: preference(id, layout)) {
                        ForEach(FeedPreference.allCases) { item in
                            Text(Copy.preference(item, language)).tag(item)
                        }
                    }
                }
                .themedSection()

                Section {
                    ForEach(HomeCard.allCases) { card in
                        HStack(spacing: 12) {
                            Toggle(Copy.card(card, language), isOn: visible(id, layout, card))
                                .accessibilityIdentifier("home-card-\(card.rawValue)")
                            Button(layout.isDetailed(card) ? (language == .zh ? "详细" : "Detail") : (language == .zh ? "基础" : "Basic")) {
                                write(layout.settingDetail(card, detailed: !layout.isDetailed(card)), id)
                            }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("detail-\(card.rawValue)")
                        }
                    }
                } header: {
                    Text(Copy.homeCards(language))
                }
                .themedSection()

                Section {
                    ForEach(layout.cards) { card in
                        HStack {
                            Text(Copy.card(card, language))
                            Spacer()
                            Button {
                                reorder(card, up: true, layout: layout, id: id)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .accessibilityLabel(language == .zh ? "上移\(Copy.card(card, language))" : "Move \(Copy.card(card, language)) up")
                            Button {
                                reorder(card, up: false, layout: layout, id: id)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .accessibilityLabel(language == .zh ? "下移\(Copy.card(card, language))" : "Move \(Copy.card(card, language)) down")
                        }
                    }
                } header: {
                    Text(language == .zh ? "首页顺序" : "Home order")
                }
                .themedSection()
    }

    private func reorder(_ card: HomeCard, up: Bool, layout: BabyHomeLayout, id: UUID) {
        write(layout.moving(card, up: up), id)
    }

    private var layoutData: Data? {
        layoutJSON.isEmpty ? nil : Data(layoutJSON.utf8)
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

    private func visible(_ id: UUID, _ layout: BabyHomeLayout, _ card: HomeCard) -> Binding<Bool> {
        Binding(
            get: { layout.cards.contains(card) },
            set: { write(layout.setting(card, visible: $0), id) }
        )
    }

    private func write(_ layout: BabyHomeLayout, _ id: UUID) {
        let data = HomeLayoutStore.save(layout, babyID: id, into: layoutData)
        layoutJSON = String(data: data, encoding: .utf8) ?? layoutJSON
    }
}
