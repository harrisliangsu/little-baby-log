import SwiftUI
import BabyLogKit

/// A sentence becomes a draft only after the person approves the exact text and then accepts the suggestion.
struct AIPhraseSheet: View {
    var task: AITask
    var seed: String
    var names: [String]
    var onRecordKind: ((EventKind) -> Void)?
    var onReminder: ((CareRule) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @State private var sentence: String
    @State private var consent: AISendPreview?
    @State private var result = ""
    @State private var pendingKind: EventKind?
    @State private var pendingRule: CareRule?

    init(task: AITask, seed: String, names: [String], onRecordKind: ((EventKind) -> Void)? = nil, onReminder: ((CareRule) -> Void)? = nil) {
        self.task = task
        self.seed = seed
        self.names = names
        self.onRecordKind = onRecordKind
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
                if let pendingKind {
                    Button(language == .zh ? "打开编辑器再保存" : "Open the editor, then save") {
                        onRecordKind?(pendingKind)
                        dismiss()
                    }
                }
                if pendingRule != nil {
                    Button(language == .zh ? "加到提醒列表" : "Add to reminders") {
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
                if let kind = draft.kind.flatMap(EventKind.init(rawValue:)) {
                    pendingKind = kind
                    result = language == .zh ? "建议类型：\(kind.rawValue)。时间若为空，编辑器里自己填，不会替你编一个。" : "Suggested type: \(kind.rawValue). If the time is empty, fill it yourself."
                } else {
                    result = language == .zh ? "没有可用的类型，没有打开编辑器。" : "No usable type, so the editor stays closed."
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
