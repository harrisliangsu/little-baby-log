import SwiftUI
import BabyLogKit

struct ManualImport: Identifiable {
    let id = UUID()
    let table: ImportTable
}

struct AssistExcerpt: Identifiable {
    let id = UUID()
    let text: String
}

/// Column choices stay on the phone. Nothing is uploaded.
struct ImportManualMapSheet: View {
    let table: ImportTable
    var onMapped: (ImportFile, Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @State private var targets: [String: String] = [:]

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(language == .zh
                         ? "在这台手机上选择每一列对应什么。不会发给 AI。"
                         : "Choose what each column means on this phone. Nothing is sent.")
                        .font(.footnote)
                }
                Section {
                    ForEach(table.headers, id: \.self) { header in
                        Picker(header, selection: binding(header)) {
                            Text(language == .zh ? "不用" : "Skip").tag("")
                            ForEach(StandardImporter.columns, id: \.self) { column in
                                Text(column).tag(column)
                            }
                        }
                    }
                }
            }
            .navigationTitle(language == .zh ? "对应列" : "Columns")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language == .zh ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language == .zh ? "检查" : "Check") { apply() }
                }
            }
        }
    }

    private func binding(_ header: String) -> Binding<String> {
        Binding(get: { targets[header] ?? "" }, set: { targets[header] = $0 })
    }

    private func apply() {
        let mappings = table.headers.map { header in
            ColumnMapping(source: header, target: (targets[header]?.isEmpty == false) ? targets[header] : nil)
        }
        let file = ImportIntake.applyManualMap(table, mappings: mappings)
        let source = StandardImporter.schemaCSV(headers: table.headers, rows: table.rows, mappings: mappings)
        onMapped(file, source)
        dismiss()
    }
}

/// Confirms, then sends only the extracted text to the current chat endpoint.
struct ImportAssistSheet: View {
    let excerpt: String
    var onFile: (ImportFile) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @State private var errorText: String?
    @State private var sending = false

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(language == .zh
                         ? "文件里的文字可能包含宝宝的健康记录，将发给当前的 AI 供应商。密钥不会发出。当前接口不能直接读二进制或未知备份。"
                         : "Text from the file may include health notes and will be sent to the current assistant. The key is not sent. This chat API cannot read raw binary or an unknown backup.")
                }
                Section {
                    Text(excerpt).font(.footnote).lineLimit(8)
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            .navigationTitle(language == .zh ? "发给当前 AI" : "Send to the assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language == .zh ? "取消" : "Cancel") { dismiss() }
                        .accessibilityIdentifier("import-assist-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language == .zh ? "确认发送" : "Send") { Task { await send() } }
                        .disabled(sending)
                        .accessibilityIdentifier("import-assist-send")
                }
            }
        }
    }

    private func send() async {
        guard AIRuntime.access().maySend else {
            errorText = language == .zh ? "AI 已关闭，没有发送。" : "The assistant is off. Nothing was sent."
            return
        }
        sending = true
        defer { sending = false }
        ImportTraffic.noteModelRequest(lane: .assisted)
        let preview = AISendPreview(
            provider: AIPreferences.provider,
            task: .columnMapping,
            userText: ImportIntake.assistPrompt(excerpt),
            removedBabyNames: false
        )
        do {
            let data = try await AIRuntime.send(preview: preview, ticket: AIFlight.shared.ticket())
            let json = try AIProposalDecoder.modelJSON(from: data)
            let file = StandardImporter.parse(data: json)
            guard file.fileProblems.isEmpty else {
                errorText = language == .zh ? "返回的内容不是标准导入格式。" : "The reply was not the standard import format."
                return
            }
            onFile(file)
            dismiss()
        } catch {
            errorText = language == .zh ? "没有发送成功。文件没有写入。" : "The send failed. Nothing was written."
        }
    }

}
