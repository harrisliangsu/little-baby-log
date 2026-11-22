import Foundation

/// A plaintext export whose top-level values are JSON text, decoded a second time.
/// Recognized by those keys, not by the file extension. Deletes are shown and never applied.
public enum BljdImporter {
    public static let keys = [
        "kExportKeyBabyInfos",
        "kExportKeyBabyHeights",
        "kExportKeyBabyWeights",
        "kExportKeyBreasts",
        "kExportKeyCraps",
        "kExportKeyFoods",
        "kExportKeyFormulas",
        "kExportKeyRemarks",
        "kExportKeySleeps",
        "kExportKeyUrines",
        "kExportKeyEvents",
        "kExportKeyDeletes",
    ]

    public static func parseIfWrapped(_ data: Data) -> ImportFile? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard keys.allSatisfy({ object[$0] is String }) else { return nil }
        return ImportFile(rows: rows(from: object), fileProblems: [])
    }

    private static func rows(from object: [String: Any]) -> [ImportRow] {
        let babies = arrays(object["kExportKeyBabyInfos"]).compactMap { item -> (String, String)? in
            guard let id = text(item["hashid"]), !id.isEmpty else { return nil }
            return (id, text(item["name"]))
        }
        let names = Dictionary(babies, uniquingKeysWith: { first, _ in first })
        var rows: [ImportRow] = []
        var line = 1
        func add(_ row: ImportRow) {
            var copy = row
            copy.line = line
            rows.append(copy)
            line += 1
        }
        for item in arrays(object["kExportKeyBabyInfos"]) {
            if text(item["gender"]) == "0" {
                add(held("宝宝 \(label(item, names: names)) 的 gender=0 含义未知，不会写入性别。"))
                break
            }
        }
        for item in arrays(object["kExportKeyUrines"]) {
            add(care(item, collection: "urines", names: names, kind: .diaper, diaper: .wet, notices: []))
        }
        for item in arrays(object["kExportKeyCraps"]) {
            let note = "crapColor=\(text(item["crapColor"])) crapAmount=\(text(item["crapAmount"])) crapShape=\(text(item["crapShape"])) 含义未知，保留原值待确认。"
            add(care(item, collection: "craps", names: names, kind: .diaper, diaper: .dirty, notices: [note]))
        }
        for item in arrays(object["kExportKeyFormulas"]) {
            add(care(
                item,
                collection: "formulas",
                names: names,
                kind: .bottle,
                diaper: nil,
                amount: number(item["formulaFedAmount"]),
                bottle: .formula,
                notices: ["formulaFedAmount 没有写单位，预览先按毫升。请确认。不会换成水量，也不会编勺数。"]
            ))
        }
        for item in arrays(object["kExportKeyFoods"]) {
            add(care(
                item,
                collection: "foods",
                names: names,
                kind: .solids,
                diaper: nil,
                food: text(item["foodName"]),
                notices: ["没有勺数，也没有食物和水的比例，不会补编。"]
            ))
        }
        for item in arrays(object["kExportKeyBreasts"]) {
            add(care(item, collection: "breasts", names: names, kind: .breastfeed, diaper: nil, notices: []))
        }
        for item in arrays(object["kExportKeySleeps"]) {
            add(care(item, collection: "sleeps", names: names, kind: .sleep, diaper: nil, notices: []))
        }
        for item in arrays(object["kExportKeyBabyHeights"]) {
            add(care(item, collection: "heights", names: names, kind: .growth, diaper: nil, length: number(item["height"]), notices: ["身高单位按来源 unit=\(text(item["unit"]))。"]))
        }
        for item in arrays(object["kExportKeyBabyWeights"]) {
            add(care(item, collection: "weights", names: names, kind: .growth, diaper: nil, weight: number(item["weight"]), notices: ["体重单位按来源 unit=\(text(item["unit"]))。"]))
        }
        for item in arrays(object["kExportKeyRemarks"]) {
            add(held("备注不是一条护理记录，不会导入。"))
        }
        for item in arrays(object["kExportKeyEvents"]) {
            add(eventRow(item, names: names))
        }
        let deletes = arrays(object["kExportKeyDeletes"])
        if !deletes.isEmpty {
            add(held("有 \(deletes.count) 条删除墓碑。不会当成新记录，也不会删除这台手机上已有的记录。"))
        }
        return rows
    }

    private static func eventRow(_ item: [String: Any], names: [String: String]) -> ImportRow {
        let type = text(item["eventType"])
        switch type {
        case "headCircumference":
            return care(item, collection: "events", names: names, kind: .growth, diaper: nil, head: number(item["headCircumference"]) ?? number(item["value"]), notices: ["头围来自事件，单位未在来源写明，请确认。"])
        case "medicine":
            return care(item, collection: "events", names: names, kind: .medicine, diaper: nil, medicine: text(item["medicineName"]).isEmpty ? text(item["name"]) : text(item["medicineName"]), notices: [])
        case "diaper", "water", "nutrition", "vaccination", "milestone", "userDefinedRecord", "foodType", "userDefinedType", "keyValue", "todo", "":
            return held("事件 \(type.isEmpty ? "未写类型" : type) 不当成护理记录导入。")
        default:
            return held("事件 \(type) 没有对应的记录类型，不会猜测。")
        }
    }

    private static func care(
        _ item: [String: Any],
        collection: String,
        names: [String: String],
        kind: EventKind,
        diaper: DiaperKind?,
        amount: Double? = nil,
        bottle: BottleContent? = nil,
        food: String = "",
        length: Double? = nil,
        weight: Double? = nil,
        head: Double? = nil,
        medicine: String = "",
        notices: [String]
    ) -> ImportRow {
        var field = ImportField()
        let hash = text(item["hashid"])
        let babyHash = text(item["babyHashid"])
        field.externalId = hash.isEmpty ? nil : "bljd:\(collection):\(hash)"
        field.kind = kind
        field.diaper = diaper
        field.amountML = amount
        field.bottleContent = bottle
        field.food = food
        field.lengthCm = length ?? 0
        field.weightKg = weight ?? 0
        field.headCm = head ?? 0
        field.medicine = medicine
        field.start = startDate(item)
        field.end = endDate(item)
        if babyHash.isEmpty {
            var row = held("没有 babyHashid，不当成护理记录。")
            row.notices = notices
            return row
        }
        let sourceName = names[babyHash] ?? ""
        field.babyName = sourceName.isEmpty ? babyHash : "\(sourceName) \(babyHash)"
        var problems: [ImportProblem] = []
        if field.start == nil { problems.append(.missingStart) }
        return ImportRow(line: 0, field: field, problems: problems, notices: notices, hold: false)
    }

    private static func held(_ notice: String) -> ImportRow {
        ImportRow(line: 0, field: ImportField(), problems: [], notices: [notice], hold: true)
    }

    private static func label(_ item: [String: Any], names: [String: String]) -> String {
        let hash = text(item["babyHashid"])
        if let name = names[hash], !name.isEmpty { return name }
        return hash.isEmpty ? "未关联" : hash
    }

    private static func arrays(_ value: Any?) -> [[String: Any]] {
        guard let text = value as? String, let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return array
    }

    private static func text(_ value: Any?) -> String {
        if let text = value as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? NSNumber { return number.doubleValue }
        let text = text(value)
        return text.isEmpty ? nil : Double(text)
    }

    private static func startDate(_ item: [String: Any]) -> Date? {
        for key in ["time", "start", "startTime", "beginTime", "recordTime", "eventTime"] {
            if let date = unix(item[key]) { return date }
        }
        let ignored: Set<String> = ["created_at", "updated_at", "restored_at", "hashid", "babyhashid", "end", "endtime", "datestring"]
        let found = item.compactMap { key, value -> Date? in
            guard !ignored.contains(key.lowercased()) else { return nil }
            return unix(value)
        }
        return found.count == 1 ? found[0] : nil
    }

    private static func endDate(_ item: [String: Any]) -> Date? {
        if let raw = item["end"] as? String, raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        return unix(item["end"]) ?? unix(item["endTime"])
    }

    private static func unix(_ value: Any?) -> Date? {
        let text = text(value)
        guard let seconds = Double(text), seconds > 1_000_000_000, seconds < 4_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
