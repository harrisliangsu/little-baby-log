import SwiftUI
import BabyLogKit

/// A sentence about records that are already on screen. Tapping a row opens that record. Nothing is written.
struct RangeSummarySheet: View {
    var total: String
    var facts: [SummaryFact]
    var names: [String]
    var onOpen: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @AppStorage(AIPreferences.enabledKey) private var aiEnabled = false
    @State private var consent: AISendPreview?
    @State private var summary = ""

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(facts) { fact in
                        Button {
                            onOpen(fact.id)
                        } label: {
                            Text(fact.line)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                if aiEnabled, AIRuntime.access().maySend {
                    Section {
                        Button(language == .zh ? "总结" : "Summarize") { consent = preview }
                            .frame(minHeight: 44)
                        if !summary.isEmpty {
                            Text(summary).font(.body)
                        }
                    }
                }
            }
            .navigationTitle(language == .zh ? "这段记录" : "These records")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language == .zh ? "关闭" : "Close") { dismiss() }
                }
            }
            .sheet(item: $consent) { preview in
                AIConsentSheet(preview: preview) {
                    AITasks.shared.run { await run(preview) }
                }
                .adoptedAppearance()
            }
        }
    }

    private var preview: AISendPreview {
        var removed = false
        let text = AIRedactor.redact(HistorySummaryText.userText(total: total, facts: facts), names: names, removed: &removed)
        return AISendPreview(provider: AIPreferences.provider, task: .rangeSummary, userText: text, removedBabyNames: removed)
    }

    private func run(_ preview: AISendPreview) async {
        let ticket = AIFlight.shared.ticket()
        guard AIRuntime.access().maySend else { return }
        do {
            let data = try await AIRuntime.send(preview: preview, ticket: ticket)
            guard AIFlight.shared.isCurrent(ticket), AIPreferences.isEnabled else { return }
            summary = try AIProposalDecoder.summary(from: data).text ?? ""
        } catch AIClientError.cancelled {
            return
        } catch is CancellationError {
            return
        } catch {
            summary = ""
        }
    }
}
