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
        let infos = arrays(object["kExportKeyBabyInfos"])
        let names = Dictionary(uniqueKeysWithValues: infos.compactMap { item -> (String, String)? in
            let id = text(item["hashid"])
            guard !id.isEmpty else { return nil }
            return (id, text(item["name"]))
        })
        var rows: [ImportRow] = []
        var line = 1
        func add(_ row: ImportRow) {
            var copy = row
            copy.line = line
            rows.append(copy)
            line += 1
        }

        for item in infos {
            let due = item["dueDate"] == nil || item["dueDate"] is NSNull ? "null" : text(item["dueDate"])
            add(held("宝宝 \(text(item["name"])) \(text(item["hashid"])) 生日 \(text(item["birthday"]))，预产期 \(due)。gender=\(text(item["gender"])) 编码未知，不写性别，也不按名字新建宝宝。"))
        }
        for item in arrays(object["kExportKeyUrines"]) {
            add(care(item, collection: "urines", names: names, kind: .diaper, diaper: .wet, startKey: "urineTime", notices: []))
        }
        for item in arrays(object["kExportKeyCraps"]) {
            let note = "crapColor=\(text(item["crapColor"])) crapAmount=\(text(item["crapAmount"])) crapShape=\(text(item["crapShape"])) 含义未知，保留原值待确认。"
            add(care(item, collection: "craps", names: names, kind: .diaper, diaper: .dirty, startKey: "crapTime", notices: [note]))
        }
        for item in arrays(object["kExportKeyFormulas"]) {
            add(care(
                item,
                collection: "formulas",
                names: names,
                kind: .bottle,
                diaper: nil,
                startKey: "formulaFedTime",
                endKey: "formulaFedEndTime",
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
                startKey: "fedTime",
                endKey: "fedEndTime",
                food: text(item["foodName"]),
                notices: ["foodItems 为空。没有勺数，也没有食物和水的比例，不会补编。"]
            ))
        }
        for item in arrays(object["kExportKeyBreasts"]) {
            let side = text(item["breastSide"])
            add(care(
                item,
                collection: "breasts",
                names: names,
                kind: .breastfeed,
                diaper: nil,
                startKey: "breastFedTime",
                endKey: "endFedTime",
                notices: ["breastSide=\(side) 含义未知，不会写成左侧或右侧。breastFedDuration=\(text(item["breastFedDuration"])) 不换算成某一侧的秒数。"]
            ))
        }
        for item in arrays(object["kExportKeySleeps"]) {
            add(care(item, collection: "sleeps", names: names, kind: .sleep, diaper: nil, startKey: "starttime", endKey: "endtime", notices: []))
        }
        for item in arrays(object["kExportKeyBabyHeights"]) {
            add(measure(item, collection: "heights", names: names, length: number(item["height"]), expectedUnit: "cm", label: "身高"))
        }
        for item in arrays(object["kExportKeyBabyWeights"]) {
            add(measure(item, collection: "weights", names: names, weight: number(item["weight"]), expectedUnit: "kg", label: "体重"))
        }
        for item in arrays(object["kExportKeyRemarks"]) {
            add(held("备注时间 \(text(item["remarkTime"]))，正文：\(text(item["remark"]))。没有对应的记录类型，不会编成其他记录。"))
        }
        for item in arrays(object["kExportKeyEvents"]) {
            add(eventRow(item, names: names))
        }
        let deletes = arrays(object["kExportKeyDeletes"])
        if !deletes.isEmpty {
            add(held("有 \(deletes.count) 条删除墓碑。snap 是已删除快照，不会当成新记录，也不会删除这台手机上已有的记录。"))
        }
        return rows
    }

    private static func eventRow(_ item: [String: Any], names: [String: String]) -> ImportRow {
        let type = text(item["eventType"])
        let valueName = text(item["valueName"])
        let value = text(item["value"])
        let note = text(item["note"])
        switch type {
        case "medicine":
            return care(item, collection: "events", names: names, kind: .medicine, diaper: nil, startKey: "eventTime", medicine: valueName, dose: value, notes: note, notices: [])
        case "nutrition":
            return care(item, collection: "events", names: names, kind: .medicine, diaper: nil, startKey: "eventTime", medicine: valueName, dose: value, notes: note, notices: ["来源类型 nutrition。名称取 valueName。value 为空就没有剂量，不会编。"])
        case "water":
            return held("喝水 value=\(value)，单位未声明。不会写成毫升。eventTime=\(text(item["eventTime"]))。")
        case "headCircumference":
            return held("头围 value=\(value)，单位未声明。不会写成厘米。eventTime=\(text(item["eventTime"]))。")
        case "vaccination":
            return held("疫苗名称在 value：\(value)。不会编成用药剂量。")
        case "milestone":
            return held("里程标题在 valueName：\(valueName)。不会编成其他记录。")
        case "userDefinedRecord":
            return held("自定义记录保留原值。eventTime=\(text(item["eventTime"])) valueName=\(valueName) value=\(value) note=\(note)。valueName 即使像毫秒，也不当作名称或时间。")
        case "diaper":
            return held("事件 diaper 不另造一条尿布。小便和大便仍按各自的 hashid 导入。")
        case "todo", "foodType", "userDefinedType", "keyValue", "":
            return held("事件 \(type.isEmpty ? "未写类型" : type) 不当成护理记录。valueName=\(valueName) value=\(value)。")
        default:
            return held("事件 \(type) 没有对应的记录类型。valueName=\(valueName) value=\(value) note=\(note)。不会猜测。")
        }
    }

    private static func measure(
        _ item: [String: Any],
        collection: String,
        names: [String: String],
        length: Double? = nil,
        weight: Double? = nil,
        expectedUnit: String,
        label: String
    ) -> ImportRow {
        let unit = text(item["unit"])
        let day = text(item["dateString"])
        guard unit == expectedUnit, let start = civilStart(day) else {
            return held("\(label) dateString=\(day) unit=\(unit) 无法按\(expectedUnit)和日期保存，没有伪造时刻。")
        }
        return care(
            item,
            collection: collection,
            names: names,
            kind: .growth,
            diaper: nil,
            start: start,
            length: length,
            weight: weight,
            notes: "只有日期 \(day)，没有时刻。",
            notices: ["\(label)只有日期 \(day)，单位 \(unit)。来源没有日内时刻，不会编成某一刻。"]
        )
    }

    private static func care(
        _ item: [String: Any],
        collection: String,
        names: [String: String],
        kind: EventKind,
        diaper: DiaperKind?,
        startKey: String? = nil,
        endKey: String? = nil,
        start: Date? = nil,
        amount: Double? = nil,
        bottle: BottleContent? = nil,
        food: String = "",
        length: Double? = nil,
        weight: Double? = nil,
        medicine: String = "",
        dose: String = "",
        notes: String = "",
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
        field.medicine = medicine
        field.dose = dose
        field.notes = notes
        field.start = start ?? startKey.flatMap { unix(item[$0]) }
        field.end = endKey.flatMap { unix(item[$0]) }
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

    private static func arrays(_ value: Any?) -> [[String: Any]] {
        guard let text = value as? String, let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return array
    }

    private static func text(_ value: Any?) -> String {
        if value is NSNull { return "" }
        if let text = value as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func number(_ value: Any?) -> Double? {
        if value is NSNull { return nil }
        if let number = value as? Double { return number }
        if let number = value as? NSNumber { return number.doubleValue }
        let text = text(value)
        return text.isEmpty ? nil : Double(text)
    }

    /// Unix seconds, either `1700000000` or `1700000000.0`. Empty means not provided. Milliseconds are not accepted.
    private static func unix(_ value: Any?) -> Date? {
        let text = text(value)
        guard !text.isEmpty, let seconds = Double(text), seconds >= 1_000_000_000, seconds < 10_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Start of that civil date in Asia/Shanghai. The source has no clock, so this is only the date boundary.
    private static func civilStart(_ day: String) -> Date? {
        let parts = day.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let zone = TimeZone(identifier: "Asia/Shanghai") else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
