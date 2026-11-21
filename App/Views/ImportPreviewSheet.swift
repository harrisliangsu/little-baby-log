import SwiftUI
import CoreData
import BabyLogKit

struct ImportRequest: Identifiable {
    let id = UUID()
    let file: ImportFile
}

/// Preview for a schema-1 file. Nothing is written until the person confirms.
struct ImportPreviewSheet: View {
    let file: ImportFile
    var onCommitted: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: Baby.lblAllByCreation()) private var babies: FetchedResults<Baby>
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @State private var assign: [String: UUID] = [:]
    @State private var errorText: String?

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
                        Text(language == .zh ? "这些名字还没有对应的宝宝" : "These names are not a baby yet")
                    } footer: {
                        Text(language == .zh ? "不会因为文件里的名字自动新建宝宝。" : "A name in the file does not create a baby.")
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
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            .navigationTitle(language == .zh ? "检查导入" : "Check import")
            .navigationBarTitleDisplayMode(.inline)
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
