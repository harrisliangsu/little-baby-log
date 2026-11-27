import SwiftUI
import CoreData
import BabyLogKit

/// Records only after the person confirms, and only when the assistant is on and a key is saved.
/// Stopping shows the exact text. Saving a draft is a separate tap. Cancel writes nothing.
struct VoiceLogSheet: View {
    let current: Baby
    var onManual: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: Baby.lblAllByCreation()) private var babies: FetchedResults<Baby>
    @StateObject private var speech = SpeechTranscriber()
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue

    @State private var phase: Phase = .disclose
    @State private var anchor: VoiceAnchor?
    @State private var transcript = ""
    @State private var preview: AISendPreview?
    @State private var nameMap: VoiceNameMap?
    @State private var consent: AISendPreview?
    @State private var drafts: [VoiceItemDraft] = []
    @State private var editing: EditingDraft?
    @State private var failure = ""

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .disclose: disclosure
                case .recording: recording
                case .preview: previewText
                case .drafts: draftList
                case .failed: failed
                }
            }
            .navigationTitle(language == .zh ? "语音" : "Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language == .zh ? "取消" : "Cancel") { abandon() }
                        .accessibilityIdentifier("voice-cancel")
                }
            }
            .sheet(item: $consent) { preview in
                AIConsentSheet(preview: preview) {
                    AITasks.shared.run { await submit(preview) }
                }
                .adoptedAppearance()
            }
            .sheet(item: $editing) { item in
                EventEditorView(baby: item.baby, target: .seeded(item.draft))
                    .adoptedAppearance()
            }
        }
        .accessibilityIdentifier("voice-disclosure")
    }

    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(language == .zh
                 ? "系统会把声音转成文字，可能会发给 Apple。录音不会发给 Kimi 或 DeepSeek，也不会留在手机里。"
                 : "The system turns speech into text and may send the sound to Apple. The recording is not sent to Kimi or DeepSeek and is not kept.")
                .font(.body)
            Button(language == .zh ? "开始" : "Start") { Task { await begin() } }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 64)
                .accessibilityIdentifier("voice-start")
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var recording: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(speech.partial.isEmpty ? (language == .zh ? "正在听" : "Listening") : speech.partial)
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            Button(language == .zh ? "停止" : "Stop") { Task { await finish() } }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 64)
                .accessibilityIdentifier("voice-stop")
        }
        .padding(20)
    }

    private var previewText: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                Text(preview?.userText ?? transcript)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            Button(language == .zh ? "发送" : "Send") { askToSend() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 56)
                .accessibilityIdentifier("voice-send")
        }
        .padding(20)
    }

    private var draftList: some View {
        List {
            ForEach(drafts) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(title(item))
                        .font(.headline)
                    if let start = item.start {
                        Text(start.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                    }
                    if !item.uncertain.isEmpty {
                        Text(badges(item))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if item.conflictsWithCurrentBaby {
                        Button(language == .zh ? "记到\(item.assignedBabyName)" : "Save to \(item.assignedBabyName)") {
                            update(item.id) { $0.confirmBaby(item.assignedBabyName) }
                        }
                        .frame(minHeight: 44)
                    } else if item.uncertain.contains(.baby) {
                        ForEach(item.candidateNames, id: \.self) { name in
                            Button(name) { update(item.id) { $0.confirmBaby(name) } }
                                .frame(minHeight: 44)
                        }
                    }
                    if item.canWrite {
                        Button(language == .zh ? "保存" : "Save") { save(item) }
                            .frame(minHeight: 44)
                    } else if item.confirmed() != nil {
                        Button(language == .zh ? "确认" : "Confirm") {
                            if let next = item.confirmed() { replace(next) }
                        }
                        .frame(minHeight: 44)
                    }
                    if item.editableDraft(fallbackStart: anchor?.startedAt ?? .now) != nil {
                        Button(language == .zh ? "修改" : "Edit") { edit(item) }
                            .frame(minHeight: 44)
                    }
                }
                .accessibilityIdentifier("voice-draft")
            }
            if drafts.contains(where: \.canWrite) {
                Button(language == .zh ? "保存已确认的" : "Save the confirmed ones") { saveReady() }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("voice-save-all")
            }
        }
    }

    private var failed: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(failure.isEmpty ? (language == .zh ? "没识别出来" : "Nothing recognized") : failure)
            Button(language == .zh ? "手动记录" : "Type it") {
                onManual()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, minHeight: 56)
            .accessibilityIdentifier("voice-manual")
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func begin() async {
        guard AIRuntime.access().mayRequestMicrophone else {
            dismiss()
            return
        }
        phase = .recording
        if let started = await speech.start() {
            anchor = started
        } else {
            failure = language == .zh ? "没识别出来" : "Nothing recognized"
            phase = .failed
        }
    }

    private func finish() async {
        let text = await speech.stop()
        switch VoiceNextStep.after(stopped: true, transcript: text, failed: text == nil) {
        case .preview:
            transcript = text ?? ""
            preparePreview()
        case .manual, .discard:
            failure = language == .zh ? "没识别出来" : "Nothing recognized"
            phase = .failed
        }
    }

    private func preparePreview() {
        guard let anchor else {
            phase = .failed
            return
        }
        let others = babies.map(\.displayName).filter { $0 != current.displayName }
        guard let outbound = VoiceDrafts.outbound(
            transcript: transcript,
            anchor: anchor,
            currentBaby: current.displayName,
            otherBabies: others,
            provider: AIPreferences.provider
        ) else {
            phase = .failed
            return
        }
        preview = outbound.preview
        nameMap = outbound.map
        phase = .preview
    }

    private func askToSend() {
        guard let preview, AIRuntime.access().maySend else {
            failure = NetworkGate.shared.isOnline
                ? (language == .zh ? "还不能使用。" : "The assistant is not ready.")
                : (language == .zh ? "没有网络。" : "No network.")
            phase = .failed
            return
        }
        consent = preview
    }

    private func submit(_ preview: AISendPreview) async {
        let ticket = AIFlight.shared.ticket()
        do {
            let data = try await AIRuntime.send(preview: preview, ticket: ticket)
            guard AIFlight.shared.isCurrent(ticket), AIPreferences.isEnabled else { return }
            guard let anchor, let nameMap else { return }
            let resolved = VoiceDrafts.resolve(items: try VoiceDrafts.items(from: data), anchor: anchor, map: nameMap)
            guard !resolved.isEmpty else {
                failure = language == .zh ? "没识别出来" : "Nothing recognized"
                phase = .failed
                return
            }
            drafts = resolved
            phase = .drafts
        } catch AIClientError.cancelled {
            return
        } catch is CancellationError {
            return
        } catch is URLError {
            failure = language == .zh ? "没有网络。" : "No network."
            phase = .failed
        } catch let error as AIClientError {
            if case .http(let code) = error, code == 401 || code == 403 {
                failure = language == .zh ? "Key 不可用。" : "The key was rejected."
            } else {
                failure = language == .zh ? "没有得到可用的回复。" : "No usable reply."
            }
            phase = .failed
        } catch {
            failure = language == .zh ? "没有得到可用的回复。" : "No usable reply."
            phase = .failed
        }
    }

    private func save(_ item: VoiceItemDraft) {
        guard persist(item) else { return }
        drafts.removeAll { $0.id == item.id }
        if drafts.isEmpty { dismiss() }
    }

    private func saveReady() {
        var remaining: [VoiceItemDraft] = []
        for item in drafts {
            if item.canWrite, persist(item) { continue }
            remaining.append(item)
        }
        drafts = remaining
        if drafts.isEmpty { dismiss() }
    }

    private func persist(_ item: VoiceItemDraft) -> Bool {
        guard let draft = item.eventDraft(),
              let target = babies.first(where: { $0.displayName == item.assignedBabyName }) else { return false }
        let event = LogEvent.create(kind: draft.kind, for: target, start: draft.startDate, in: context)
        draft.apply(to: event)
        return context.saveIfNeeded()
    }

    private func edit(_ item: VoiceItemDraft) {
        guard let form = item.editableDraft(fallbackStart: anchor?.startedAt ?? .now),
              let baby = babies.first(where: { $0.displayName == item.assignedBabyName }) else { return }
        drafts.removeAll { $0.id == item.id }
        editing = EditingDraft(id: item.id, baby: baby, draft: form)
    }

    private func update(_ id: UUID, _ change: (inout VoiceItemDraft) -> Void) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        change(&drafts[index])
    }

    private func replace(_ item: VoiceItemDraft) {
        guard let index = drafts.firstIndex(where: { $0.id == item.id }) else { return }
        drafts[index] = item
    }

    private func abandon() {
        speech.cancel()
        dismiss()
    }

    private func title(_ item: VoiceItemDraft) -> String {
        guard let kind = item.kind else { return language == .zh ? "待确认" : "Unconfirmed" }
        if language == .zh {
            if kind == .bottle, let bottle = item.bottle { return Zh.bottle(bottle) }
            return Zh.kind(kind)
        }
        return kind.title
    }

    private func badges(_ item: VoiceItemDraft) -> String {
        item.uncertain.map { uncertainty in
            switch uncertainty {
            case .baby: return language == .zh ? "宝宝待确认" : "Baby unconfirmed"
            case .kind: return language == .zh ? "类型待确认" : "Type unconfirmed"
            case .time: return language == .zh ? "时间待确认" : "Time unconfirmed"
            case .amount: return language == .zh ? "数量待确认" : "Amount unconfirmed"
            case .detail: return language == .zh ? "待确认" : "Unconfirmed"
            }
        }.joined(separator: " ")
    }
}

private struct EditingDraft: Identifiable {
    var id: UUID
    var baby: Baby
    var draft: EventDraft
}

private enum Phase {
    case disclose, recording, preview, drafts, failed
}
