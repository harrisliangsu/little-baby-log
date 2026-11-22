import SwiftUI
import BabyLogKit

/// The assistant switch, provider, model, and key status. A saved key is not a successful connection.
struct AISettingsView: View {
    var notice: String = ""
    @EnvironmentObject private var desk: AIDesk
    @AppStorage(AIPreferences.enabledKey) private var enabled = false
    @AppStorage(AIPreferences.providerKey) private var providerRaw = AIProviderID.deepseek.rawValue
    @AppStorage(AIPreferences.modelsKey) private var modelsJSON = ""
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @State private var draft = ""
    @State private var replacing = false
    @State private var savedNote = false

    private var provider: AIProviderID { AIProviderID(rawValue: providerRaw) ?? .deepseek }
    private var phase: AICredentialPhase { desk.phase(for: provider) }
    private var modelID: String { AIModelSelection(json: modelsJSON).current(for: provider) }
    private var modelTitle: String {
        AIModelCatalog.choices(for: provider).first { $0.rawID == modelID }?.title ?? modelID
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { modelID },
            set: { modelsJSON = AIModelSelection(json: modelsJSON).choosing($0, for: provider).json }
        )
    }
    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }
    private var showsKeyField: Bool {
        phase == .unconfigured || replacing
    }

    var body: some View {
        Form {
            if !notice.isEmpty {
                Text(notice)
            }
            Toggle(language == .zh ? "使用 AI 助手" : "Use the assistant", isOn: $enabled)
                .accessibilityIdentifier("ai-enabled")
            Picker(language == .zh ? "供应商" : "Provider", selection: $providerRaw) {
                ForEach(AIProviderID.allCases) { item in
                    Text(item.displayName).tag(item.rawValue)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("ai-provider")
            Picker(language == .zh ? "模型" : "Model", selection: modelSelection) {
                ForEach(AIModelCatalog.choices(for: provider)) { choice in
                    Text(choice.title).tag(choice.rawID)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("ai-model")
            status
            if showsKeyField {
                SecureField(language == .zh ? "API Key" : "API key", text: $draft)
                    .accessibilityIdentifier("ai-key-field")
                Button(language == .zh ? "保存在这台设备" : "Save on this device") {
                    saveKey()
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("ai-save-key")
                if replacing {
                    Button(language == .zh ? "取消" : "Cancel") {
                        draft = ""
                        replacing = false
                    }
                }
            }
        }
        .navigationTitle(language == .zh ? "AI 助手" : "Assistant")
        .onChange(of: enabled) { _, isOn in
            if !isOn { AITasks.shared.cancelAll() }
        }
        .onChange(of: providerRaw) { _, _ in
            replacing = false
            draft = ""
            savedNote = false
        }
    }

    @ViewBuilder
    private var status: some View {
        switch phase {
        case .unconfigured:
            EmptyView()
        case .savedUnverified:
            savedRow
            if savedNote {
                Text(language == .zh ? "已保存在这台设备" : "Saved on this device")
                    .font(.footnote)
            }
            if enabled {
                Button(language == .zh ? "验证" : "Check") { Task { await desk.verify(provider) } }
                    .accessibilityIdentifier("ai-verify")
            }
        case .checking:
            HStack {
                ProgressView()
                Text(modelTitle)
            }
            .accessibilityIdentifier("ai-key-status")
        case .verified:
            Text(modelTitle)
                .accessibilityIdentifier("ai-key-status")
            savedRow
        case .rejected:
            Text(language == .zh ? "Key 不可用" : "The key was rejected")
                .accessibilityIdentifier("ai-key-status")
            savedRow
            if enabled { retry }
        case .offline:
            Text(language == .zh ? "没有网络" : "No network")
                .accessibilityIdentifier("ai-key-status")
            savedRow
            if enabled { retry }
        case .unavailable:
            Text(language == .zh ? "没有得到回复" : "No reply")
                .accessibilityIdentifier("ai-key-status")
            savedRow
            if enabled { retry }
        }
    }

    private var savedRow: some View {
        let last = AIKeyStore.lastFour(provider: provider)
        return HStack {
            Text(last.isEmpty ? (language == .zh ? "已保存" : "Saved") : "····\(last)")
                .accessibilityIdentifier("ai-key-status")
            Spacer()
            Button(language == .zh ? "更换" : "Replace") {
                replacing = true
                savedNote = false
            }
            .accessibilityIdentifier("ai-replace-key")
            Button(language == .zh ? "删除" : "Delete", role: .destructive) {
                AIKeyStore.delete(provider: provider)
                desk.noteDeleted(provider)
                draft = ""
                replacing = false
                savedNote = false
            }
        }
    }

    private var retry: some View {
        Button(language == .zh ? "重试" : "Try again") { Task { await desk.verify(provider) } }
            .accessibilityIdentifier("ai-verify")
    }

    private func saveKey() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        AIKeyStore.save(trimmed, provider: provider)
        desk.noteSaved(provider)
        draft = ""
        replacing = false
        savedNote = true
    }
}
