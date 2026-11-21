import SwiftUI
import BabyLogKit

/// Optional assistant. Off until a key is saved here. Nothing is sent from this screen except a connection test the person confirms.
struct AISettingsView: View {
    var notice: String = ""
    @AppStorage(AIPreferences.enabledKey) private var enabled = false
    @AppStorage(AIPreferences.providerKey) private var providerRaw = AIProviderID.deepseek.rawValue
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @State private var draft = ""
    @State private var savedHint = ""
    @State private var message = ""

    private var provider: AIProviderID { AIProviderID(rawValue: providerRaw) ?? .deepseek }

    private var modelSelection: Binding<String> {
        Binding(
            get: { AIPreferences.modelID(for: provider) },
            set: { AIPreferences.setModel($0, for: provider) }
        )
    }
    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
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
            SecureField(language == .zh ? "API Key" : "API key", text: $draft)
            if !savedHint.isEmpty {
                Text(language == .zh ? "已保存，末四位 \(savedHint)" : "Saved, last four \(savedHint)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button(language == .zh ? "保存在这台设备" : "Save on this device") {
                let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                AIKeyStore.save(trimmed, provider: provider)
                UserDefaults.standard.set(false, forKey: AIPreferences.rejectedKey)
                draft = ""
                savedHint = AIKeyStore.lastFour(provider: provider)
            }
            Button(language == .zh ? "删除 Key" : "Delete key", role: .destructive) {
                AIKeyStore.delete(provider: provider)
                AITasks.shared.cancelAll()
                savedHint = ""
            }
            Text(language == .zh ? "Key 只在这台手机，不同步。" : "The key stays on this phone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !message.isEmpty {
                Text(message).font(.footnote)
            }
        }
        .navigationTitle(language == .zh ? "AI 助手" : "Assistant")
        .onAppear { savedHint = AIKeyStore.lastFour(provider: provider) }
        .onChange(of: enabled) { _, isOn in
            if !isOn { AITasks.shared.cancelAll() }
        }
    }
}
