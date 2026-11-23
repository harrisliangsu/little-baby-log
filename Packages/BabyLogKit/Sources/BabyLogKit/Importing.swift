import Foundation

// Local import of the versioned schema described in docs/import-and-ai.md.
// Parsed rows are values. Nothing here talks to a model, a network, or Core Data.
// A file that is not schema 1 is rejected. This does not claim to read any other app.

public enum ImportProblem: Equatable, Sendable {
    case badEncoding
    case unsupportedVersion
    case missingHeader
    case badDate
    case missingStart
    case endBeforeStart
    case unknownKind(String)
    case unknownUnit(String)
    case unknownValue(String)
    case missingAmount
    case amountNeedsReview
    case unmappedBaby
}

public struct ImportField: Equatable, Sendable {
    public var babyName: String
    public var babyId: UUID?
    public var externalId: String?
    public var kind: EventKind?
    public var start: Date?
    public var end: Date?
    public var amountML: Double?
    public var bottleContent: BottleContent?
    public var leftSeconds: Double
    public var rightSeconds: Double
    public var diaper: DiaperKind?
    public var food: String
    public var pumpedLeftML: Double
    public var pumpedRightML: Double
    public var weightKg: Double
    public var lengthCm: Double
    public var headCm: Double
    public var medicine: String
    public var dose: String
    public var notes: String

    public init() {
        babyName = ""
        leftSeconds = 0
        rightSeconds = 0
        food = ""
        pumpedLeftML = 0
        pumpedRightML = 0
        weightKg = 0
        lengthCm = 0
        headCm = 0
        medicine = ""
        dose = ""
        notes = ""
    }
}

public struct ImportRow: Equatable, Sendable, Identifiable {
    public var line: Int
    public var field: ImportField
    public var problems: [ImportProblem]
    /// Shown in the preview. They do not block a confirmed insert.
    public var notices: [String] = []
    /// Kept visible, but never inserted and never used to delete existing rows.
    public var hold: Bool = false

    public var id: Int { line }

    /// A row with any problem stays in the preview and is not inserted.
    public var blocksImport: Bool { !problems.isEmpty }
}

public struct ImportFile: Equatable, Sendable {
    public var rows: [ImportRow]
    public var fileProblems: [ImportProblem]
}

public enum ImportAction: Equatable, Sendable {
    case insert
    case skipIdempotent
    case skipCandidate
    case blocked
    case unmappedBaby
    /// Explained in the preview. Not inserted, and not a delete of existing data.
    case hold
}

public struct PlannedImport: Equatable, Sendable {
    public var line: Int
    public var action: ImportAction
    public var problems: [ImportProblem]
    public var babyID: UUID?
}

public struct KnownBaby: Equatable, Sendable {
    public var id: UUID
    public var name: String
    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct KnownEvent: Equatable, Sendable {
    public var babyID: UUID
    public var externalID: String?
    public var kind: EventKind
    public var start: Date
    public var amountML: Double
    public var bottleContent: BottleContent?
    public var diaper: DiaperKind?
    public var food: String
    public var medicine: String
    public var dose: String

    public init(
        babyID: UUID,
        externalID: String? = nil,
        kind: EventKind,
        start: Date,
        amountML: Double = 0,
        bottleContent: BottleContent? = nil,
        diaper: DiaperKind? = nil,
        food: String = "",
        medicine: String = "",
        dose: String = ""
    ) {
        self.babyID = babyID
        self.externalID = externalID
        self.kind = kind
        self.start = start
        self.amountML = amountML
        self.bottleContent = bottleContent
        self.diaper = diaper
        self.food = food
        self.medicine = medicine
        self.dose = dose
    }
}

public enum StandardImporter {
    public static let schema = "littlebabylog.import"
    public static let version = 1
    public static let columns = [
        "schemaVersion", "babyName", "babyId", "externalId", "kind", "start", "end",
        "amountML", "amountUnit", "bottleContent", "leftSeconds", "rightSeconds", "diaper",
        "food", "pumpedLeftML", "pumpedRightML", "weightKg", "lengthCm", "headCm",
        "medicine", "dose", "notes",
    ]

    /// Reads headers and cells without requiring the standard schema. Used to build a mapping preview.
    public static func rawTable(data: Data) -> (headers: [String], rows: [[String: String]])? {
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        if text.hasPrefix("\u{feff}") { text.removeFirst() }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") { return nil }
        var lines = splitLines(text)
        if lines.first?.hasPrefix("#") == true { lines.removeFirst() }
        guard let headerLine = lines.first else { return nil }
        let headers = parseCSVLine(headerLine)
        let rows = lines.dropFirst().compactMap { line -> [String: String]? in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
            let cells = parseCSVLine(line)
            var dict: [String: String] = [:]
            for (index, name) in headers.enumerated() where index < cells.count {
                dict[name] = cells[index]
            }
            return dict
        }
        return (headers, rows)
    }

    /// Builds a schema-1 CSV from a column mapping. Unmapped sources are dropped. Nothing is written to the store.
    public static func schemaCSV(headers: [String], rows: [[String: String]], mappings: [ColumnMapping]) -> Data {
        let bySource = Dictionary(uniqueKeysWithValues: mappings.compactMap { mapping -> (String, String)? in
            guard let target = mapping.target else { return nil }
            return (mapping.source, target)
        })
        var lines = ["# littlebabylog.import 1", columns.joined(separator: ",")]
        for row in rows {
            var values: [String: String] = [:]
            for (source, cell) in row {
                if let target = bySource[source] { values[target] = cell }
            }
            if values["schemaVersion"] == nil { values["schemaVersion"] = "1" }
            lines.append(columns.map { field($0, values[$0] ?? "") }.joined(separator: ","))
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    public static func parse(data: Data) -> ImportFile {
        guard var text = String(data: data, encoding: .utf8) else {
            return ImportFile(rows: [], fileProblems: [.badEncoding])
        }
        if text.hasPrefix("\u{feff}") { text.removeFirst() }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return parseJSON(text) }
        return parseCSV(text)
    }

    public static func plan(
        file: ImportFile,
        babies: [KnownBaby],
        events: [KnownEvent],
        assign: [String: UUID] = [:]
    ) -> [PlannedImport] {
        file.rows.map { row in
            if row.hold {
                return PlannedImport(line: row.line, action: .hold, problems: row.problems, babyID: nil)
            }
            if row.blocksImport {
                return PlannedImport(line: row.line, action: .blocked, problems: row.problems, babyID: nil)
            }
            guard let babyID = babyID(for: row.field, babies: babies, assign: assign) else {
                return PlannedImport(line: row.line, action: .unmappedBaby, problems: row.problems + [.unmappedBaby], babyID: nil)
            }
            if let external = row.field.externalId, events.contains(where: { $0.babyID == babyID && $0.externalID == external }) {
                return PlannedImport(line: row.line, action: .skipIdempotent, problems: row.problems, babyID: babyID)
            }
            if let kind = row.field.kind, let start = row.field.start,
               events.contains(where: { samePayload($0, babyID: babyID, kind: kind, start: start, field: row.field) }) {
                return PlannedImport(line: row.line, action: .skipCandidate, problems: row.problems, babyID: babyID)
            }
            return PlannedImport(line: row.line, action: .insert, problems: row.problems, babyID: babyID)
        }
    }

    // MARK: Parsing

    private static func parseJSON(_ text: String) -> ImportFile {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ImportFile(rows: [], fileProblems: [.unsupportedVersion])
        }
        guard (object["schema"] as? String) == schema, (object["schemaVersion"] as? Int) == version else {
            return ImportFile(rows: [], fileProblems: [.unsupportedVersion])
        }
        guard let rows = object["rows"] as? [[String: Any]] else {
            return ImportFile(rows: [], fileProblems: [.missingHeader])
        }
        return ImportFile(rows: rows.enumerated().map { index, row in parseFields(row, line: index + 1) }, fileProblems: [])
    }

    private static func parseCSV(_ text: String) -> ImportFile {
        var lines = splitLines(text)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "# littlebabylog.import 1" {
            lines.removeFirst()
        } else if lines.first?.hasPrefix("#") == true {
            return ImportFile(rows: [], fileProblems: [.unsupportedVersion])
        }
        guard let headerLine = lines.first else { return ImportFile(rows: [], fileProblems: [.missingHeader]) }
        let header = parseCSVLine(headerLine)
        guard Set(header) == Set(columns) else { return ImportFile(rows: [], fileProblems: [.missingHeader]) }
        let records = lines.dropFirst().enumerated().compactMap { offset, line -> ImportRow? in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
            let cells = parseCSVLine(line)
            var dict: [String: String] = [:]
            for (index, name) in header.enumerated() where index < cells.count {
                dict[name] = cells[index]
            }
            return parseFields(dict.mapValues { $0 as Any }, line: offset + 2)
        }
        return ImportFile(rows: records, fileProblems: [])
    }

    private static func parseFields(_ raw: [String: Any], line: Int) -> ImportRow {
        var field = ImportField()
        var problems: [ImportProblem] = []
        field.babyName = string(raw["babyName"])
        field.babyId = UUID(uuidString: string(raw["babyId"]))
        let external = string(raw["externalId"])
        field.externalId = external.isEmpty ? nil : external
        let kindText = string(raw["kind"])
        if let kind = EventKind(rawValue: kindText) {
            field.kind = kind
        } else {
            problems.append(.unknownKind(kindText))
        }
        if let start = date(raw["start"]) {
            field.start = start
        } else if string(raw["start"]).isEmpty {
            problems.append(.missingStart)
        } else {
            problems.append(.badDate)
        }
        if !string(raw["end"]).isEmpty {
            if let end = date(raw["end"]) {
                field.end = end
            } else {
                problems.append(.badDate)
            }
        }
        if let start = field.start, let end = field.end, end < start {
            problems.append(.endBeforeStart)
        }
        let unit = string(raw["amountUnit"]).isEmpty ? "ml" : string(raw["amountUnit"])
        if !string(raw["amountML"]).isEmpty {
            if let amount = Double(string(raw["amountML"])) {
                switch unit {
                case "ml": field.amountML = amount
                case "oz": field.amountML = VolumeUnit.ounces.milliliters(from: amount)
                default: problems.append(.unknownUnit(unit))
                }
                if let ml = field.amountML, ml < 0 || ml > 2000 { problems.append(.amountNeedsReview) }
            } else {
                problems.append(.unknownValue(string(raw["amountML"])))
            }
        } else if field.kind == .bottle {
            problems.append(.missingAmount)
        }
        if !string(raw["bottleContent"]).isEmpty {
            if let content = BottleContent(rawValue: string(raw["bottleContent"])) {
                field.bottleContent = content
            } else {
                problems.append(.unknownValue(string(raw["bottleContent"])))
            }
        }
        field.leftSeconds = Double(string(raw["leftSeconds"])) ?? 0
        field.rightSeconds = Double(string(raw["rightSeconds"])) ?? 0
        if !string(raw["diaper"]).isEmpty {
            if let diaper = DiaperKind(rawValue: string(raw["diaper"])) {
                field.diaper = diaper
            } else {
                problems.append(.unknownValue(string(raw["diaper"])))
            }
        }
        field.food = string(raw["food"])
        field.pumpedLeftML = Double(string(raw["pumpedLeftML"])) ?? 0
        field.pumpedRightML = Double(string(raw["pumpedRightML"])) ?? 0
        field.weightKg = Double(string(raw["weightKg"])) ?? 0
        field.lengthCm = Double(string(raw["lengthCm"])) ?? 0
        field.headCm = Double(string(raw["headCm"])) ?? 0
        field.medicine = string(raw["medicine"])
        field.dose = string(raw["dose"])
        field.notes = string(raw["notes"])
        return ImportRow(line: line, field: field, problems: problems)
    }

    private static func string(_ value: Any?) -> String {
        if let text = value as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func date(_ value: Any?) -> Date? {
        let text = string(value)
        guard !text.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return formatter.date(from: text)
    }

    private static func babyID(for field: ImportField, babies: [KnownBaby], assign: [String: UUID]) -> UUID? {
        if let id = field.babyId, babies.contains(where: { $0.id == id }) { return id }
        let key = field.babyName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let chosen = assign[key] { return chosen }
        return babies.first { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }?.id
    }

    private static func samePayload(_ event: KnownEvent, babyID: UUID, kind: EventKind, start: Date, field: ImportField) -> Bool {
        guard event.babyID == babyID, event.kind == kind, abs(event.start.timeIntervalSince(start)) < 1 else { return false }
        switch kind {
        case .bottle:
            return abs(event.amountML - (field.amountML ?? 0)) < 0.01 && event.bottleContent == (field.bottleContent ?? .formula)
        case .diaper:
            return event.diaper == field.diaper
        case .solids:
            return event.food == field.food
        case .medicine:
            return event.medicine == field.medicine && event.dose == field.dose
        default:
            return true
        }
    }

    private static func splitLines(_ text: String) -> [String] {
        var lines: [String] = []
        var current = ""
        var quoted = false
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            let character = chars[index]
            if character == "\"" {
                current.append(character)
                if quoted, index + 1 < chars.count, chars[index + 1] == "\"" {
                    current.append(chars[index + 1])
                    index += 1
                } else {
                    quoted.toggle()
                }
            } else if !quoted && (character == "\n" || character == "\r") {
                lines.append(current)
                current = ""
                if character == "\r", index + 1 < chars.count, chars[index + 1] == "\n" { index += 1 }
            } else {
                current.append(character)
            }
            index += 1
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    private static func field(_ name: String, _ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var quoted = false
        var iterator = line.makeIterator()
        while let character = iterator.next() {
            if character == "\"" {
                if quoted, let peek = iterator.next() {
                    if peek == "\"" { current.append("\"") } else {
                        quoted = false
                        if peek == "," {
                            cells.append(current)
                            current = ""
                        } else {
                            current.append(peek)
                        }
                    }
                } else if quoted {
                    quoted = false
                } else {
                    quoted = true
                }
            } else if character == "," && !quoted {
                cells.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current)
        return cells
    }
}
