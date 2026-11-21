import SwiftUI
import BabyLogKit

/// Optional assistant. Off until a key is saved here. Nothing is sent from this screen except a connection test the person confirms.
struct AISettingsView: View {
    @AppStorage(AIPreferences.enabledKey) private var enabled = false
    @AppStorage(AIPreferences.providerKey) private var providerRaw = AIProviderID.deepseek.rawValue
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @State private var draft = ""
    @State private var savedHint = ""
    @State private var message = ""

    private var provider: AIProviderID { AIProviderID(rawValue: providerRaw) ?? .deepseek }
    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    var body: some View {
        Form {
            Toggle(language == .zh ? "使用 AI 助手" : "Use the assistant", isOn: $enabled)
            Picker(language == .zh ? "供应商" : "Provider", selection: $providerRaw) {
                ForEach(AIProviderID.allCases) { item in
                    Text(item.displayName).tag(item.rawValue)
                }
            }
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
                draft = ""
                savedHint = AIKeyStore.lastFour(provider: provider)
            }
            Button(language == .zh ? "删除 Key" : "Delete key", role: .destructive) {
                AIKeyStore.delete(provider: provider)
                savedHint = ""
            }
            Text(language == .zh
                 ? "Key 只在这台手机的钥匙串里，不同步到 iCloud。没有 Key 时，记录、同步和标准导入都照常可用。这里不会自动上传记录。"
                 : "The key stays in this phone's Keychain and is not synced. Records, sync, and standard import work with no key. Nothing is uploaded from this screen automatically.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !message.isEmpty {
                Text(message).font(.footnote)
            }
        }
        .navigationTitle(language == .zh ? "AI 助手" : "Assistant")
        .onAppear { savedHint = AIKeyStore.lastFour(provider: provider) }
    }
}
