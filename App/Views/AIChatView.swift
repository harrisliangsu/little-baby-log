import SwiftUI
import UIKit
import CoreData
import BabyLogKit

/// One chat for this baby. Voice, typed notes, summaries, and import mappings land here.
/// Nothing is stored until a record card is confirmed. The thread stays on `AIDesk` if this screen closes.
struct AIChatView: View {
    let baby: Baby
    var summaryTotal: String?
    var summaryFacts: [SummaryFact] = []
    var mapping: AISendPreview?
    var reminder = false
    var onOpenFact: ((String) -> Void)?
    var onMapping: (([ColumnMapping]) -> Void)?
    var onReminder: ((CareRule) -> Void)?

    @EnvironmentObject private var desk: AIDesk
    @EnvironmentObject private var voice: VoiceSession
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: Baby.lblAllByCreation()) private var babies: FetchedResults<Baby>
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @State private var composer = ""
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
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if thread.messages.isEmpty && summaryFacts.isEmpty {
                                Text(language == .zh ? "可以问问题，也可以说出要记的事。" : "Ask a question, or say what to log.")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(summaryFacts) { fact in
                                Button(fact.line) { onOpenFact?(fact.id) }
                                    .frame(minHeight: 44)
                            }
                            ForEach(thread.messages) { message in
                                messageRow(message).id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: thread.messages.count) { _, _ in
                        if let last = thread.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .accessibilityIdentifier("ai-chat")
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) { composerBar }
                .overlay(alignment: .bottom) {
                    if voice.isPresented {
                        VoiceCapturePanel(voice: voice, language: language) { text in
                            let id = desk.addDraft(baby: babyID, text: text)
                            if let message = desk.thread(for: babyID).messages.first(where: { $0.id == id }) {
                                prepareSend(message)
                            }
                        }
                    }
                }
            }
            .navigationTitle(baby.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                seed()
                flushPending()
            }
            .onChange(of: desk.pendingSend) { _, _ in flushPending() }
            .sheet(item: $editing) { item in
                EventEditorView(baby: item.baby, target: .seeded(item.draft))
            }
            .sheet(item: $desk.pendingForm) { form in
                EventEditorView(baby: baby, target: .seeded(form.draft), onFinish: { saved in
                    desk.finishForm(saved: saved)
                })
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: AIChatMessage) -> some View {
        let mine = message.role == .user
        HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 8) {
                Text(shown(message.text))
                    .textSelection(.enabled)
                    .padding(12)
                    .background(mine ? Color.accentColor.opacity(0.9) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(mine ? Color.white : Color.primary)
                if !mine, !message.text.isEmpty {
                    Button(language == .zh ? "复制" : "Copy") {
                        UIPasteboard.general.string = shown(message.text)
                    }
                    .font(.footnote)
                    .accessibilityIdentifier("ai-copy")
                }
                deliveryControls(message)
            }
            if !mine { Spacer(minLength: 40) }
        }
    }

    private func shown(_ text: String) -> String {
        let clean = ChatSurface.present(text).text
        return clean.isEmpty ? (language == .zh ? "请在表单里确认后再保存。" : "Review the form, then save.") : clean
    }

    @ViewBuilder
    private func deliveryControls(_ message: AIChatMessage) -> some View {
        let mine = message.role == .user
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
                VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                    Text((message.failure ?? .unread).text(chinese: language == .zh))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("ai-chat-error")
                    Button(language == .zh ? "重试" : "Try again") { prepareSend(message) }
                        .frame(minHeight: 44)
                }
            case .cancelled:
                Text(language == .zh ? "已取消" : "Cancelled")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .sent:
                EmptyView()
            }
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
        HStack(alignment: .bottom, spacing: 4) {
            TextField(language == .zh ? "记一条" : "Note", text: $composer, axis: .vertical)
                .lineLimit(1...6)
                .padding(.leading, 16)
                .padding(.vertical, 12)
                .accessibilityIdentifier("ai-chat-input")
            Image(systemName: "mic.fill")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if voice.machine.phase == .idle, AIRuntime.access() == .ready {
                                voice.pressDown()
                            }
                            voice.move(value.translation.height)
                        }
                        .onEnded { _ in
                            if voice.machine.phase == .holding || voice.machine.phase == .recording {
                                voice.release()
                            }
                        }
                )
                .accessibilityIdentifier("ai-chat-mic")
            Button(action: sendComposer) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .frame(width: 44, height: 44)
            }
            .disabled(composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("ai-chat-send")
            .accessibilityLabel(language == .zh ? "发送" : "Send")
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .accessibilityIdentifier("composer-bar")
    }

    private func sendComposer() {
        let text = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let id = desk.addDraft(baby: babyID, text: text)
        composer = ""
        if let message = desk.thread(for: babyID).messages.first(where: { $0.id == id }) {
            prepareSend(message)
        }
    }

    private func textBinding(_ message: AIChatMessage) -> Binding<String> {
        Binding(
            get: { desk.thread(for: babyID).messages.first { $0.id == message.id }?.text ?? message.text },
            set: { desk.replaceText(baby: babyID, id: message.id, text: $0) }
        )
    }

    private func flushPending() {
        guard let pending = desk.pendingSend, pending.baby == babyID,
              let message = desk.thread(for: babyID).messages.first(where: { $0.id == pending.message }) else { return }
        desk.pendingSend = nil
        prepareSend(message)
    }

    private func seed() {
        if let summaryTotal, let id = desk.seed(baby: babyID, key: "summary-\(summaryTotal)", text: summaryTotal),
           let message = desk.thread(for: babyID).messages.first(where: { $0.id == id }) {
            prepareSend(message)
        }
        if let mapping, let id = desk.seed(baby: babyID, key: "mapping-\(mapping.id)", text: language == .zh ? "看列名" : "Columns"),
           let message = desk.thread(for: babyID).messages.first(where: { $0.id == id }) {
            prepareSend(message)
        }
        if reminder {
            desk.seed(baby: babyID, key: "reminder", text: "")
        }
    }

    private func prepareSend(_ message: AIChatMessage) {
        guard message.delivery == .draft || message.delivery == .failed else { return }
        let catalog = AIConfigurationCatalog.load()
        guard let active = catalog.active else {
            desk.setDelivery(baby: babyID, id: message.id, delivery: .failed, failure: .noProvider)
            return
        }
        let access = AIRuntime.access()
        guard access.maySend else {
            desk.setDelivery(baby: babyID, id: message.id, delivery: .failed, failure: AIChatFailure.from(access: access))
            return
        }
        let preview: AISendPreview
        if let mapping {
            preview = AISendPreview(
                provider: active.provider,
                task: mapping.task,
                userText: mapping.userText,
                removedBabyNames: mapping.removedBabyNames
            )
        } else if summaryTotal != nil {
            preview = AISendPreview(
                provider: active.provider,
                task: .rangeSummary,
                userText: HistorySummaryText.userText(total: message.text, facts: summaryFacts),
                removedBabyNames: false
            )
        } else if reminder {
            preview = AISendPreview(
                provider: active.provider,
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
                provider: active.provider
            ) else { return }
            preview = outbound.preview
        }
        AITasks.shared.run { await submit(preview, message: message.id) }
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
                    desk.setDelivery(baby: babyID, id: id, delivery: .failed, failure: .unread)
                    return
                }
                let anchor: FeedIntervalAnchor = draft.anchor == "end" ? .end : .start
                let rule = CareRule(reminderText: text, source: .anyFeed, trigger: .intervalSinceLast(minutes: minutes, anchor: anchor))
                desk.setDelivery(baby: babyID, id: id, delivery: .sent)
                onReminder?(rule)
                return
            }
            let spoken = desk.thread(for: babyID).messages.first { $0.id == id }?.text ?? ""
            let others = babies.map(\.displayName).filter { $0 != baby.displayName }
            let map = VoiceDrafts.redact(transcript: spoken, currentBaby: baby.displayName, otherBabies: others).map
            let updated = try AIChatExchange.apply(
                response: data,
                to: desk.thread(for: babyID),
                message: id,
                anchor: VoiceAnchor(startedAt: anchor, timeZone: .current),
                map: map
            )
            desk.replaceThread(updated)
            let records = desk.thread(for: babyID).messages.first { $0.id == id }?.records ?? []
            if records.contains(where: { $0.conflictsWithCurrentBaby }) {
                desk.appendReply(baby: babyID, text: language == .zh ? "这句话像是在记另一位宝宝，没有打开表单。" : "That sounded like another baby, so no form was opened.")
            } else {
                let drafts = records.compactMap { $0.editableDraft(fallbackStart: anchor) }
                if !drafts.isEmpty {
                    desk.appendReply(baby: babyID, text: language == .zh ? "请在表单里看过再保存。" : "Review the form, then save.")
                    desk.offerForms(drafts)
                }
            }
        } catch AIClientError.cancelled, is CancellationError {
            desk.cancel(baby: babyID, id: id)
        } catch {
            desk.setDelivery(baby: babyID, id: id, delivery: .failed, failure: AIChatFailure.from(error))
        }
    }

    private func persist(_ item: VoiceItemDraft) -> Bool {
        AIChatCommit.save(item, babies: Array(babies), in: context)
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
