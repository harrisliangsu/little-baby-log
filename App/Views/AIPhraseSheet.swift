import SwiftUI
import BabyLogKit

/// A sentence becomes a draft only after the person approves the exact text and then accepts the suggestion.
struct AIPhraseSheet: View {
    var task: AITask
    var seed: String
    var names: [String]
    var onRecord: ((RecordDraftSuggestion) -> Void)?
    var onReminder: ((CareRule) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @State private var sentence: String
    @State private var consent: AISendPreview?
    @State private var result = ""
    @State private var pendingRecord: RecordDraftSuggestion?
    @State private var pendingRule: CareRule?

    init(task: AITask, seed: String, names: [String], onRecord: ((RecordDraftSuggestion) -> Void)? = nil, onReminder: ((CareRule) -> Void)? = nil) {
        self.task = task
        self.seed = seed
        self.names = names
        self.onRecord = onRecord
        self.onReminder = onReminder
        _sentence = State(initialValue: seed)
    }

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    var body: some View {
        NavigationStack {
            Form {
                if task != .rangeSummary {
                    TextField(language == .zh ? "想记的话" : "What to say", text: $sentence, axis: .vertical)
                } else {
                    Text(sentence).font(.footnote)
                }
                Button(language == .zh ? "查看将发送的内容" : "Review what would be sent") {
                    consent = preview
                }
                .disabled(sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !result.isEmpty {
                    Text(result).font(.footnote)
                }
                if let pendingRecord {
                    Button(language == .zh ? "在记录表单里检查" : "Review in the entry form") {
                        onRecord?(pendingRecord)
                        dismiss()
                    }
                }
                if pendingRule != nil {
                    Button(language == .zh ? "在提醒表单里检查" : "Review in the reminder form") {
                        if let pendingRule { onReminder?(pendingRule) }
                        dismiss()
                    }
                }
            }
            .navigationTitle(language == .zh ? "草稿" : "Draft")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language == .zh ? "关闭" : "Close") { dismiss() }
                }
            }
            .sheet(item: $consent) { preview in
                AIConsentSheet(preview: preview) {
                    Task { await run(preview) }
                }
            }
        }
    }

    private var preview: AISendPreview {
        var removed = false
        let redacted = AIRedactor.redact(sentence, names: names, removed: &removed)
        let instruction: String
        switch task {
        case .recordDraft:
            instruction = "Return json with kind, start, amountML, note. Use null when unknown. kind is one of sleep, breastfeed, bottle, diaper."
        case .reminderDraft:
            instruction = "Return json with text, minutes, anchor. anchor is start or end. Do not invent a medical recommendation."
        case .rangeSummary:
            instruction = "Return json with text. Summarize only the counts below. No medical advice."
        case .columnMapping, .connectionTest:
            instruction = "Return json."
        }
        return AISendPreview(provider: AIPreferences.provider, task: task, userText: instruction + "\n" + redacted, removedBabyNames: removed)
    }

    private func run(_ preview: AISendPreview) async {
        guard let token = AIKeyStore.token(provider: preview.provider) else { return }
        do {
            let data = try await AIClient(transport: LockedHostTransport()).send(
                provider: preview.provider, preview: preview, token: token, approved: preview
            )
            switch task {
            case .recordDraft:
                let draft = try AIProposalDecoder.record(from: data)
                if draft.kind.flatMap(EventKind.init(rawValue:)) != nil {
                    pendingRecord = draft
                    result = language == .zh ? "已得到一条可编辑的记录建议。打开表单后才会保存。" : "There is an editable record suggestion. It is saved only from the form."
                } else {
                    result = language == .zh ? "没有可用的类型，没有打开表单。" : "No usable type, so the form stays closed."
                }
            case .reminderDraft:
                let draft = try AIProposalDecoder.reminder(from: data)
                let text = draft.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty, let minutes = draft.minutes else {
                    result = language == .zh ? "没有完整的提醒建议。" : "The reminder suggestion was incomplete."
                    return
                }
                let anchor: FeedIntervalAnchor = draft.anchor == "end" ? .end : .start
                pendingRule = CareRule(reminderText: text, source: .anyFeed, trigger: .intervalSinceLast(minutes: minutes, anchor: anchor))
                result = language == .zh ? "建议：\(text)，\(minutes) 分钟，从\(anchor == .end ? "结束" : "开始")算。" : "Suggestion: \(text), \(minutes) min."
            case .rangeSummary:
                result = try AIProposalDecoder.summary(from: data).text ?? ""
            default:
                break
            }
        } catch {
            result = language == .zh ? "没有得到可用的回复，没有保存任何东西。" : "No usable reply, and nothing was saved."
        }
    }
}
