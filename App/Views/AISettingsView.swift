import SwiftUI
import BabyLogKit

/// Assistant switch plus one card per saved provider. A saved key is not a verified connection.
struct AISettingsView: View {
    var notice: String = ""
    @EnvironmentObject private var desk: AIDesk
    @AppStorage(AIPreferences.enabledKey) private var enabled = false
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @State private var catalog = AIConfigurationCatalog.load()
    @State private var sheet: ProviderSheet?
    @State private var pendingDelete: UUID?

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
            Section {
                ForEach(catalog.items) { item in
                    providerCard(item)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button(language == .zh ? "设为当前" : "Use") { activate(item.id) }
                            Button(language == .zh ? "编辑" : "Edit") { sheet = .edit(item.id) }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(language == .zh ? "删除" : "Delete", role: .destructive) {
                                pendingDelete = item.id
                            }
                        }
                }
                Button(language == .zh ? "添加供应商" : "Add a provider") {
                    sheet = .add
                }
                .accessibilityIdentifier("add-provider")
            } footer: {
                Text(language == .zh
                     ? "保存只表示 Key 在这台手机上。验证通过才算连上。删除当前供应商后，需要再点一次「设为当前」。"
                     : "Saving keeps the key on this phone. A check is a separate step. Deleting the current provider does not switch to another.")
            }
        }
        .navigationTitle(language == .zh ? "AI 助手" : "Assistant")
        .onChange(of: enabled) { _, isOn in
            if !isOn { AITasks.shared.cancelAll() }
        }
        .sheet(item: $sheet) { item in
            ProviderConfigSheet(mode: item, catalog: $catalog)
        }
        .confirmationDialog(
            language == .zh ? "删除这个供应商？" : "Delete this provider?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(language == .zh ? "删除" : "Delete", role: .destructive) {
                if let id = pendingDelete { remove(id) }
            }
            Button(language == .zh ? "取消" : "Cancel", role: .cancel) {}
        }
    }

    private func providerCard(_ item: AIProviderConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.provider.displayName).font(.headline)
                if catalog.activeID == item.id {
                    Text(language == .zh ? "当前" : "Current")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                Spacer()
                Menu {
                    Button(language == .zh ? "设为当前" : "Use") { activate(item.id) }
                    Button(language == .zh ? "编辑" : "Edit") { sheet = .edit(item.id) }
                    Button(language == .zh ? "删除" : "Delete", role: .destructive) { pendingDelete = item.id }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("provider-menu-\(item.id.uuidString)")
            }
            Text(modelTitle(item))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(status(item))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.provider.displayName) \(modelTitle(item)) \(status(item))")
    }

    private func modelTitle(_ item: AIProviderConfiguration) -> String {
        AIModelCatalog.choices(for: item.provider).first { $0.rawID == item.model }?.title ?? item.model
    }

    private func status(_ item: AIProviderConfiguration) -> String {
        let last = AIKeyStore.lastFour(account: item.id.uuidString)
        let phase = desk.phase(for: item.provider)
        if last.isEmpty { return language == .zh ? "未保存 Key" : "No key" }
        if catalog.activeID == item.id, phase == .verified {
            return language == .zh ? "已验证 ····\(last)" : "Checked ····\(last)"
        }
        return language == .zh ? "已保存，未验证 ····\(last)" : "Saved, not checked ····\(last)"
    }

    private func activate(_ id: UUID) {
        AITasks.shared.cancelAll()
        catalog = catalog.activating(id)
        catalog.save()
    }

    private func remove(_ id: UUID) {
        AITasks.shared.cancelAll()
        AIKeyStore.delete(account: id.uuidString)
        catalog = catalog.deleting(id)
        catalog.save()
        pendingDelete = nil
    }
}

private enum ProviderSheet: Identifiable {
    case add
    case edit(UUID)
    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let id): return id.uuidString
        }
    }
}

private struct ProviderConfigSheet: View {
    let mode: ProviderSheet
    @Binding var catalog: AIConfigurationCatalog
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var desk: AIDesk
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @State private var provider: AIProviderID
    @State private var model: String
    @State private var draft = ""
    @State private var choosing = true

    init(mode: ProviderSheet, catalog: Binding<AIConfigurationCatalog>) {
        self.mode = mode
        _catalog = catalog
        switch mode {
        case .add:
            _provider = State(initialValue: .deepseek)
            _model = State(initialValue: AIModelCatalog.defaultID(for: .deepseek))
            _choosing = State(initialValue: true)
        case .edit(let id):
            let item = catalog.wrappedValue.items.first { $0.id == id }
            _provider = State(initialValue: item?.provider ?? .deepseek)
            _model = State(initialValue: item?.model ?? AIModelCatalog.defaultID(for: .deepseek))
            _choosing = State(initialValue: false)
        }
    }

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    var body: some View {
        NavigationStack {
            Form {
                if choosing {
                    Section {
                        providerButton(.deepseek, language == .zh ? "对话接口" : "Chat API")
                        providerButton(.kimiAI, "api.moonshot.ai")
                        providerButton(.kimiCN, "api.moonshot.cn")
                    }
                } else {
                    Picker(language == .zh ? "模型" : "Model", selection: $model) {
                        ForEach(AIModelCatalog.choices(for: provider)) { choice in
                            Text(choice.title).tag(choice.rawID)
                        }
                    }
                    .accessibilityIdentifier("ai-model")
                    SecureField(language == .zh ? "API Key" : "API key", text: $draft)
                        .accessibilityIdentifier("ai-key-field")
                    Button(language == .zh ? "保存在这台设备" : "Save on this device") { save() }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && modeID == nil)
                        .accessibilityIdentifier("ai-save-key")
                }
            }
            .navigationTitle(choosing ? (language == .zh ? "添加供应商" : "Add a provider") : provider.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language == .zh ? "取消" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private var modeID: UUID? {
        if case .edit(let id) = mode { return id }
        return nil
    }

    private func providerButton(_ item: AIProviderID, _ detail: String) -> some View {
        Button {
            provider = item
            model = AIModelCatalog.defaultID(for: item)
            choosing = false
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("provider-\(item.rawValue)")
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = modeID ?? UUID()
        if !trimmed.isEmpty {
            AIKeyStore.save(trimmed, account: id.uuidString)
        }
        var next = catalog
        if let index = next.items.firstIndex(where: { $0.id == id }) {
            next.items[index].model = AIModelCatalog.resolve(model, for: provider)
        } else if !trimmed.isEmpty {
            next.items.append(AIProviderConfiguration(id: id, provider: provider, model: model))
            if next.activeID == nil { next.activeID = id }
        } else {
            return
        }
        next.save()
        catalog = next
        desk.noteSaved(provider)
        dismiss()
    }
}
