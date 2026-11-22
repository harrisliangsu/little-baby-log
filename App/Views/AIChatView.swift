import SwiftUI
import CoreData
import BabyLogKit

/// One chat for this baby. Voice, typed notes, summaries, and import mappings land here.
/// Nothing is stored until a record card is confirmed. The thread stays on `AIDesk` if this screen closes.
struct AIChatView: View {
    let baby: Baby
    var startVoice = false
    var summaryTotal: String?
    var summaryFacts: [SummaryFact] = []
    var mapping: AISendPreview?
    var reminder = false
    var onOpenFact: ((String) -> Void)?
    var onMapping: (([ColumnMapping]) -> Void)?
    var onReminder: ((CareRule) -> Void)?

    @EnvironmentObject private var desk: AIDesk
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: Baby.lblAllByCreation()) private var babies: FetchedResults<Baby>
    @StateObject private var speech = SpeechTranscriber()
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @State private var voice: VoiceStep?
    @State private var composer = ""
    @State private var consent: AISendPreview?
    @State private var pendingID: UUID?
    @State private var anchor = Date()
    @State private var editing: EditingDraft?

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }
    private var babyID: UUID {
        baby.uuid ?? UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    }
    private var thread: AIChatThread { desk.thread(for: babyID) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let voice {
                    voicePanel(voice)
                }
                List {
                    if !summaryFacts.isEmpty {
                        Section {
                            ForEach(summaryFacts) { fact in
                                Button(fact.line) { onOpenFact?(fact.id) }
                                    .frame(minHeight: 44)
                            }
                        }
                    }
                    ForEach(thread.messages) { message in
                        messageRow(message)
                    }
                }
                .accessibilityIdentifier("ai-chat")
                composerBar
            }
            .navigationTitle(baby.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: seed)
            .sheet(item: $consent) { preview in
                AIConsentSheet(preview: preview) {
                    guard let pendingID else { return }
                    AITasks.shared.run { await submit(preview, message: pendingID) }
                }
            }
            .sheet(item: $editing) { item in
                EventEditorView(baby: item.baby, target: .seeded(item.draft))
            }
        }
    }

    @ViewBuilder
    private func voicePanel(_ step: VoiceStep) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch step {
            case .disclose:
                Text(language == .zh
                     ? "系统会把声音转成文字，可能会发给 Apple。录音不会发给 Kimi 或 DeepSeek，也不会留在手机里。"
                     : "The system may send speech to Apple. The recording is not sent to the model and is not kept.")
                Button(language == .zh ? "开始" : "Start") { Task { await beginVoice() } }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("voice-start")
            case .recording:
                Text(speech.partial.isEmpty ? (language == .zh ? "正在听" : "Listening") : speech.partial)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                Button(language == .zh ? "停止" : "Stop") { Task { await finishVoice() } }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("voice-stop")
            }
            Button(language == .zh ? "取消" : "Cancel") {
                speech.cancel()
                voice = nil
            }
            .accessibilityIdentifier("voice-cancel")
        }
        .padding()
        .accessibilityIdentifier("voice-disclosure")
    }

    @ViewBuilder
    private func messageRow(_ message: AIChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.delivery == .draft || message.delivery == .failed {
                TextField(language == .zh ? "草稿" : "Draft", text: textBinding(message), axis: .vertical)
            } else {
                Text(message.text)
            }
            switch message.delivery {
            case .draft:
                Button(language == .zh ? "发送" : "Send") { prepareSend(message) }
                    .frame(minHeight: 44)
            case .sending:
                HStack {
                    ProgressView()
                    Button(language == .zh ? "取消" : "Cancel") {
                        AITasks.shared.cancelAll()
                        desk.cancel(baby: babyID, id: message.id)
                    }
                }
            case .failed:
                Button(language == .zh ? "重试" : "Try again") { prepareSend(message) }
                    .frame(minHeight: 44)
            case .cancelled:
                Text(language == .zh ? "已取消" : "Cancelled")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .sent:
                EmptyView()
            }
            ForEach(message.records) { item in
                recordCard(item, message: message.id)
            }
        }
        .padding(.vertical, 4)
    }

    private func recordCard(_ item: VoiceItemDraft, message: UUID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.kind.map { language == .zh ? Zh.kind($0) : $0.title } ?? (language == .zh ? "待确认" : "Unconfirmed"))
            if item.uncertain.isEmpty == false {
                Text(language == .zh ? "待确认" : "Unconfirmed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if item.canWrite {
                Button(language == .zh ? "保存" : "Save") {
                    if persist(item) { dropRecord(item, message: message) }
                }
                .frame(minHeight: 44)
            } else if item.conflictsWithCurrentBaby {
                Button(language == .zh ? "记到\(item.assignedBabyName)" : item.assignedBabyName) {
                    var next = item
                    next.confirmBaby(item.assignedBabyName)
                    replaceRecord(next, message: message)
                }
                .frame(minHeight: 44)
            }
        }
    }

    private var composerBar: some View {
        HStack(spacing: 8) {
            TextField(language == .zh ? "记一条" : "Note", text: $composer, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("ai-chat-input")
            Button(language == .zh ? "发送" : "Send") {
                let text = composer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                let id = desk.addDraft(baby: babyID, text: text)
                composer = ""
                if let message = desk.thread(for: babyID).messages.first(where: { $0.id == id }) {
                    prepareSend(message)
                }
            }
            .frame(minHeight: 44)
            .disabled(composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("ai-chat-send")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func textBinding(_ message: AIChatMessage) -> Binding<String> {
        Binding(
            get: { desk.thread(for: babyID).messages.first { $0.id == message.id }?.text ?? message.text },
            set: { desk.replaceText(baby: babyID, id: message.id, text: $0) }
        )
    }

    private func seed() {
        if startVoice, voice == nil { voice = .disclose }
        if let summaryTotal {
            desk.seed(baby: babyID, key: "summary-\(summaryTotal)", text: summaryTotal)
        }
        if let mapping {
            desk.seed(baby: babyID, key: "mapping-\(mapping.id)", text: mapping.userText)
        }
        if reminder {
            desk.seed(baby: babyID, key: "reminder", text: "")
        }
    }

    private func beginVoice() async {
        guard AIRuntime.access().mayRequestMicrophone else { return }
        voice = .recording
        if let started = await speech.start() {
            anchor = started.startedAt
        } else {
            voice = nil
            _ = desk.addDraft(baby: babyID, text: language == .zh ? "没识别出来" : "Nothing recognized")
        }
    }

    private func finishVoice() async {
        let text = await speech.stop()
        voice = nil
        switch VoiceNextStep.after(stopped: true, transcript: text, failed: text == nil) {
        case .preview:
            _ = desk.addDraft(baby: babyID, text: text ?? "")
        case .manual, .discard:
            _ = desk.addDraft(baby: babyID, text: "")
        }
    }

    private func prepareSend(_ message: AIChatMessage) {
        guard AIRuntime.access().maySend else { return }
        guard message.delivery == .draft || message.delivery == .failed else { return }
        let preview: AISendPreview
        if mapping != nil {
            preview = AISendPreview(provider: AIPreferences.provider, task: .columnMapping, userText: message.text, removedBabyNames: true)
        } else if summaryTotal != nil {
            preview = AISendPreview(
                provider: AIPreferences.provider,
                task: .rangeSummary,
                userText: HistorySummaryText.userText(total: message.text, facts: summaryFacts),
                removedBabyNames: false
            )
        } else if reminder {
            preview = AISendPreview(
                provider: AIPreferences.provider,
                task: .reminderDraft,
                userText: "Return json with text, minutes, anchor. anchor is start or end.\n" + message.text,
                removedBabyNames: false
            )
        } else {
            let others = babies.map(\.displayName).filter { $0 != baby.displayName }
            guard let outbound = VoiceDrafts.outbound(
                transcript: message.text,
                anchor: VoiceAnchor(startedAt: anchor, timeZone: .current),
                currentBaby: baby.displayName,
                otherBabies: others,
                provider: AIPreferences.provider
            ) else { return }
            preview = outbound.preview
        }
        pendingID = message.id
        consent = preview
    }

    private func submit(_ preview: AISendPreview, message id: UUID) async {
        desk.setDelivery(baby: babyID, id: id, delivery: .sending)
        let ticket = AIFlight.shared.ticket()
        do {
            let data = try await AIRuntime.send(preview: preview, ticket: ticket)
            guard AIPreferences.isEnabled, AIFlight.shared.isCurrent(ticket) else {
                desk.cancel(baby: babyID, id: id)
                return
            }
            if mapping != nil {
                let columns = try AIProposalDecoder.columns(from: data)
                desk.setDelivery(baby: babyID, id: id, delivery: .sent)
                onMapping?(columns)
                return
            }
            if summaryTotal != nil {
                let text = try AIProposalDecoder.summary(from: data).text ?? ""
                desk.setText(baby: babyID, id: id, text: text)
                desk.setDelivery(baby: babyID, id: id, delivery: .sent)
                return
            }
            if reminder {
                let draft = try AIProposalDecoder.reminder(from: data)
                let text = draft.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty, let minutes = draft.minutes else {
                    desk.setDelivery(baby: babyID, id: id, delivery: .failed)
                    return
                }
                let anchor: FeedIntervalAnchor = draft.anchor == "end" ? .end : .start
                let rule = CareRule(reminderText: text, source: .anyFeed, trigger: .intervalSinceLast(minutes: minutes, anchor: anchor))
                desk.setDelivery(baby: babyID, id: id, delivery: .sent)
                onReminder?(rule)
                return
            }
            let others = babies.map(\.displayName).filter { $0 != baby.displayName }
            let map = VoiceDrafts.redact(transcript: preview.userText, currentBaby: baby.displayName, otherBabies: others).map
            let records = VoiceDrafts.resolve(
                items: try VoiceDrafts.items(from: data),
                anchor: VoiceAnchor(startedAt: anchor, timeZone: .current),
                map: map
            )
            desk.finish(baby: babyID, id: id, records: records)
        } catch AIClientError.cancelled, is CancellationError {
            desk.cancel(baby: babyID, id: id)
        } catch {
            desk.setDelivery(baby: babyID, id: id, delivery: .failed)
        }
    }

    private func persist(_ item: VoiceItemDraft) -> Bool {
        guard let draft = item.eventDraft(),
              let target = babies.first(where: { $0.displayName == item.assignedBabyName }) else { return false }
        let event = LogEvent.create(kind: draft.kind, for: target, start: draft.startDate, in: context)
        draft.apply(to: event)
        return context.saveIfNeeded()
    }

    private func dropRecord(_ item: VoiceItemDraft, message: UUID) {
        guard var thread = Optional(desk.thread(for: babyID)),
              let index = thread.messages.firstIndex(where: { $0.id == message }) else { return }
        thread.messages[index].records.removeAll { $0.id == item.id }
        desk.replaceThread(thread)
    }

    private func replaceRecord(_ item: VoiceItemDraft, message: UUID) {
        guard var thread = Optional(desk.thread(for: babyID)),
              let index = thread.messages.firstIndex(where: { $0.id == message }),
              let record = thread.messages[index].records.firstIndex(where: { $0.id == item.id }) else { return }
        thread.messages[index].records[record] = item
        desk.replaceThread(thread)
    }
}

private enum VoiceStep {
    case disclose, recording
}

private struct EditingDraft: Identifiable {
    var id: UUID
    var baby: Baby
    var draft: EventDraft
}
