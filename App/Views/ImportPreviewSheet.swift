import SwiftUI
import CoreData
import BabyLogKit

struct ImportRequest: Identifiable {
    let id = UUID()
    let file: ImportFile
    let source: Data
}

/// Preview for a schema-1 file. Nothing is written until the person confirms.
struct ImportPreviewSheet: View {
    @State private var file: ImportFile
    let source: Data
    var onCommitted: (UUID) -> Void

    init(file: ImportFile, source: Data, onCommitted: @escaping (UUID) -> Void) {
        _file = State(initialValue: file)
        self.source = source
        self.onCommitted = onCommitted
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: Baby.lblAllByCreation()) private var babies: FetchedResults<Baby>
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @State private var assign: [String: UUID] = [:]
    @State private var errorText: String?
    @State private var showMappingChat = false
    @State private var mappingText = ""

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    private var knownBabies: [KnownBaby] {
        babies.compactMap { baby in
            guard let id = baby.uuid else { return nil }
            return KnownBaby(id: id, name: baby.displayName)
        }
    }

    private var knownEvents: [KnownEvent] {
        let request = LogEvent.fetchRequest()
        let events = (try? context.fetch(request)) ?? []
        return events.compactMap { event in
            guard let babyID = event.baby?.uuid, let start = event.startDate else { return nil }
            return KnownEvent(
                babyID: babyID, externalID: event.externalID, kind: event.kind, start: start,
                amountML: event.amountML, bottleContent: event.bottleContent, diaper: event.diaperKind,
                food: event.foodName ?? "", medicine: event.medicineName ?? "", dose: event.dose ?? ""
            )
        }
    }

    private var plan: [PlannedImport] {
        StandardImporter.plan(file: file, babies: knownBabies, events: knownEvents, assign: assign)
    }

    var body: some View {
        NavigationStack {
            List {
                if !file.fileProblems.isEmpty {
                    Section {
                        ForEach(file.fileProblems.indices, id: \.self) { index in
                            Text(label(file.fileProblems[index]))
                        }
                    } header: {
                        Text(language == .zh ? "文件不能导入" : "This file cannot be imported")
                    }
                }
                Section {
                    LabeledContent(language == .zh ? "将新增" : "Will add", value: "\(plan.filter { $0.action == .insert }.count)")
                    LabeledContent(language == .zh ? "已导入过" : "Already imported", value: "\(plan.filter { $0.action == .skipIdempotent }.count)")
                    LabeledContent(language == .zh ? "可能重复" : "Possible duplicates", value: "\(plan.filter { $0.action == .skipCandidate }.count)")
                    LabeledContent(language == .zh ? "有问题" : "Problems", value: "\(plan.filter { $0.action == .blocked }.count)")
                }
                let missing = Set(plan.filter { $0.action == .unmappedBaby }.map(\.line))
                if !missing.isEmpty {
                    Section {
                        ForEach(file.rows.filter { missing.contains($0.line) }, id: \.line) { row in
                            Picker(row.field.babyName, selection: assignment(row.field.babyName)) {
                                Text(language == .zh ? "先不导入" : "Skip for now").tag(Optional<UUID>.none)
                                ForEach(knownBabies, id: \.id) { baby in
                                    Text(baby.name).tag(Optional(baby.id))
                                }
                            }
                        }
                    } header: {
                        Text(language == .zh ? "对应宝宝" : "Baby")
                    }
                }
                Section {
                    ForEach(file.rows.filter { !$0.problems.isEmpty }) { row in
                        Text(language == .zh ? "第 \(row.line) 行" : "Line \(row.line)")
                        ForEach(row.problems.indices, id: \.self) { index in
                            Text(label(row.problems[index]))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if AIRuntime.access().maySend {
                    Section {
                        Button(language == .zh ? "看列名" : "Columns") {
                            guard AIRuntime.access().maySend else { return }
                            showMappingChat = true
                        }
                        if !mappingText.isEmpty {
                            Text(mappingText).font(.footnote)
                        }
                    }
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            .navigationTitle(language == .zh ? "检查导入" : "Check import")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showMappingChat) {
                if let baby = babies.first {
                    AIChatView(baby: baby, mapping: mappingPreview, onMapping: { columns in
                        mappingText = columns.map { "\($0.source) → \($0.target ?? "—")" }.joined(separator: "\n")
                        if let table = StandardImporter.rawTable(data: source) {
                            let rebuilt = StandardImporter.schemaCSV(headers: table.headers, rows: table.rows, mappings: columns)
                            file = StandardImporter.parse(data: rebuilt)
                        }
                    })
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language == .zh ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language == .zh ? "导入" : "Import") { commit() }
                        .disabled(plan.allSatisfy { $0.action != .insert } || !file.fileProblems.isEmpty)
                }
            }
        }
    }

    private func assignment(_ name: String) -> Binding<UUID?> {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Binding(
            get: { assign[key] },
            set: { assign[key] = $0 }
        )
    }

    private var mappingPreview: AISendPreview {
        let names = file.rows.map(\.field.babyName)
        let rows = file.rows.prefix(8).map { row in
            [row.field.kind?.rawValue ?? "", row.field.notes.isEmpty ? "" : "[text]"]
        }
        let sample = AIRedactor.mappingSample(headers: ["kind", "notes"], rows: rows, babyNames: names)
        let text = "Return json. columns is an array of {source, target}. target is a standard column or null.\n" + sample.text
        return AISendPreview(provider: AIPreferences.provider, task: .columnMapping, userText: text, removedBabyNames: sample.removedNames)
    }

    private func commit() {
        var map: [UUID: Baby] = [:]
        for baby in babies {
            if let id = baby.uuid { map[id] = baby }
        }
        do {
            let result = try ImportCommit.apply(file: file, plan: plan, babies: map, in: context)
            onCommitted(result.batchID)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func label(_ problem: ImportProblem) -> String {
        switch problem {
        case .badEncoding: return language == .zh ? "不是 UTF-8" : "Not UTF-8"
        case .unsupportedVersion: return language == .zh ? "不是 littlebabylog.import 版本 1" : "Not littlebabylog.import version 1"
        case .missingHeader: return language == .zh ? "表头对不上标准列" : "The header is not the standard columns"
        case .badDate: return language == .zh ? "日期缺少时区偏移" : "A date is missing its time-zone offset"
        case .missingStart: return language == .zh ? "没有开始时间" : "Missing start"
        case .endBeforeStart: return language == .zh ? "结束早于开始" : "End is before start"
        case .unknownKind(let value): return language == .zh ? "不认识的类型 \(value)" : "Unknown type \(value)"
        case .unknownUnit(let value): return language == .zh ? "不认识的单位 \(value)" : "Unknown unit \(value)"
        case .unknownValue(let value): return language == .zh ? "不认识的取值 \(value)" : "Unknown value \(value)"
        case .missingAmount: return language == .zh ? "没有奶量" : "Missing amount"
        case .amountNeedsReview: return language == .zh ? "奶量需要再看一眼" : "Amount needs a look"
        case .unmappedBaby: return language == .zh ? "还没有对应宝宝" : "No matching baby"
        }
    }
}
