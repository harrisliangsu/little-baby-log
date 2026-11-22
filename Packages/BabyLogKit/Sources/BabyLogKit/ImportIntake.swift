import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// Two doors into the same writer. The ordinary door never builds a model request.
public enum ImportLane: String, Sendable {
    case ordinary
    case assisted
}

public enum ImportTraffic {
    public private(set) static var modelRequests = 0

    public static func reset() { modelRequests = 0 }

    /// Only the assisted door, after the person confirms, may call this.
    public static func noteModelRequest(lane: ImportLane) {
        guard lane == .assisted else { return }
        modelRequests += 1
    }
}

public struct ImportTable: Equatable, Sendable {
    public var headers: [String]
    public var rows: [[String: String]]
}

public enum ImportOrdinaryResult: Equatable, Sendable {
    case schema(ImportFile)
    case manual(ImportTable)
    case rejected(String)
}

public enum ImportAssistResult: Equatable, Sendable {
    /// Already our schema. Do not call a model.
    case schema(ImportFile)
    /// Text the current chat endpoint can read, after the person confirms.
    case text(String)
    /// The integrated chat API cannot read this body. Nothing is uploaded.
    case unsupported(String)
}

/// Local file intake. Format details stay here. The assisted door does not ask which app made the file.
public enum ImportIntake {
    public static let maxBytes = 8_000_000
    public static let maxExcerpt = 12_000

    public static let ordinaryFormats = "普通导入：标准 CSV / JSON，或表头不同的 CSV（在手机上选列）。不调用模型。"
    public static let assistedFormats = "AI 导入：直接选文件。能读出的文字在确认后发给当前供应商。当前接入是文字对话，不能上传任意二进制。"

    public static func openOrdinary(data: Data, filename: String) -> ImportOrdinaryResult {
        switch body(data, filename: filename) {
        case .rejected(let message):
            return .rejected(message)
        case .schema(let file):
            return .schema(file)
        case .table(let table):
            return .manual(table)
        case .prose:
            return .rejected("这不是表格或标准 JSON。普通导入不会把它发给 AI。")
        }
    }

    public static func openAssisted(data: Data, filename: String) -> ImportAssistResult {
        switch body(data, filename: filename) {
        case .rejected(let message):
            return .unsupported(message)
        case .schema(let file):
            return .schema(file)
        case .table(let table):
            let lines = ([table.headers.joined(separator: ",")] + table.rows.prefix(80).map { row in
                table.headers.map { row[$0] ?? "" }.joined(separator: ",")
            }).joined(separator: "\n")
            return .text(excerpt(lines))
        case .prose(let text):
            return .text(excerpt(text))
        }
    }

    public static func applyManualMap(_ table: ImportTable, mappings: [ColumnMapping]) -> ImportFile {
        let data = StandardImporter.schemaCSV(headers: table.headers, rows: table.rows, mappings: mappings)
        return StandardImporter.parse(data: data)
    }

    /// Instructions plus the excerpt. The key is never included.
    public static func assistPrompt(_ excerpt: String) -> String {
        """
        把下面的文字转成 littlebabylog.import JSON。schema 必须是 littlebabylog.import，schemaVersion 为 1。\
        不确定的类型、时间或宝宝不要猜，该字段留空。不要因为小便再造一条尿布。只返回 JSON。
        \(excerpt)
        """
    }

    private enum Body: Equatable {
        case schema(ImportFile)
        case table(ImportTable)
        case prose(String)
        case rejected(String)
    }

    private static func body(_ data: Data, filename: String) -> Body {
        if data.count > maxBytes {
            return .rejected("文件超过 8MB，没有读取，也没有上传。")
        }
        let name = filename.lowercased()
        if data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])) || data.starts(with: Data([0xFF, 0xD8, 0xFF])) {
            return .rejected("这是图片。当前文字对话接口不能读图片，文件没有上传。")
        }
        if data.starts(with: Data("%PDF-".utf8)) {
            if let text = pdfText(data) {
                return .prose(text)
            }
            return .rejected("这份 PDF 没有可提取的文字，或已加密。没有上传原始文件。")
        }
        if data.starts(with: Data("SQLite format 3".utf8)) {
            return .rejected("这是 SQLite 数据库。这一版不读取，也没有发给 AI。")
        }
        if data.starts(with: Data([0x50, 0x4B, 0x03, 0x04])) {
            return .rejected(zipMessage(data))
        }
        guard let text = String(data: data, encoding: .utf8) else {
            if name.hasSuffix(".bljd") {
                return .rejected("这是 .bljd 备份。还没有真实样本确认内部格式，不会按 ZIP、JSON 或数据库去猜，也没有发给 AI。")
            }
            return .rejected("文件不是可读取的文字。没有把二进制发给 AI。")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .rejected("文件是空的。")
        }
        if trimmed.hasPrefix("{") {
            let file = StandardImporter.parse(data: data)
            if file.fileProblems.isEmpty || !file.rows.isEmpty {
                return .schema(file)
            }
            return .prose(trimmed)
        }
        if looksLikeHTML(trimmed) {
            let stripped = stripTags(trimmed)
            return stripped.isEmpty ? .rejected("网页里没有读出文字。没有上传。") : .prose(stripped)
        }
        if let table = StandardImporter.rawTable(data: data), table.headers.count > 1 {
            if Set(table.headers) == Set(StandardImporter.columns) || trimmed.contains("littlebabylog.import") {
                return .schema(StandardImporter.parse(data: data))
            }
            return .table(ImportTable(headers: table.headers, rows: table.rows))
        }
        if name.hasSuffix(".bljd") {
            return .rejected("扩展名是 .bljd，内容也不是已知表格。还不能确认这种备份的结构，没有发给 AI。")
        }
        return .prose(trimmed)
    }

    /// Looks at ZIP local headers only. Does not inflate, so a claimed huge size cannot expand in memory.
    private static func zipMessage(_ data: Data) -> String {
        var offset = 0
        var entries = 0
        var claimed: UInt64 = 0
        let bytes = [UInt8](data.prefix(65_536))
        while offset + 30 <= bytes.count && entries < 64 {
            if bytes[offset] != 0x50 || bytes[offset + 1] != 0x4B || bytes[offset + 2] != 0x03 || bytes[offset + 3] != 0x04 {
                break
            }
            let flags = UInt16(bytes[offset + 6]) | (UInt16(bytes[offset + 7]) << 8)
            if flags & 1 != 0 {
                return "这是加密的 ZIP。没有解密，也没有发给 AI。"
            }
            let compressed = u32(bytes, offset + 18)
            let uncompressed = u32(bytes, offset + 22)
            let nameLength = Int(UInt16(bytes[offset + 26]) | (UInt16(bytes[offset + 27]) << 8))
            let extraLength = Int(UInt16(bytes[offset + 28]) | (UInt16(bytes[offset + 29]) << 8))
            claimed += UInt64(uncompressed)
            if claimed > 32_000_000 || uncompressed > 32_000_000 {
                return "压缩包声明的体积过大，已停止。没有解压，也没有发给 AI。"
            }
            let next = offset + 30 + nameLength + extraLength + Int(compressed)
            if next < offset { break }
            offset = next
            entries += 1
        }
        return "文件头是 ZIP。还不知道里面的记录格式，这一版不展开，也没有发给 AI。"
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func excerpt(_ text: String) -> String {
        if text.count <= maxExcerpt { return text }
        return String(text.prefix(maxExcerpt))
    }

    private static func pdfText(_ data: Data) -> String? {
        #if canImport(PDFKit)
        guard let document = PDFDocument(data: data), !document.isLocked, !document.isEncrypted else { return nil }
        let pageCount = min(document.pageCount, 20)
        var pages: [String] = []
        for index in 0..<pageCount {
            guard let page = document.page(at: index), let text = page.string, !text.isEmpty else { continue }
            pages.append(text)
        }
        let joined = pages.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
        #else
        return nil
        #endif
    }

    private static func looksLikeHTML(_ text: String) -> Bool {
        let head = text.prefix(200).lowercased()
        return head.contains("<html") || head.contains("<table") || head.contains("<!doctype html")
    }

    private static func stripTags(_ text: String) -> String {
        var output = ""
        var inside = false
        for character in text {
            if character == "<" { inside = true; continue }
            if character == ">" { inside = false; output.append(" "); continue }
            if !inside { output.append(character) }
        }
        return output.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
