import Foundation

// Optional on-device calls to Kimi or DeepSeek. No backend. The model only proposes
// candidates. It never writes Core Data, never receives tools, and is not called
// unless the person approves the exact text about to be sent.

public enum AIProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case kimiAI
    case kimiCN
    case deepseek

    public var id: String { rawValue }

    /// Fixed hosts from the vendor docs checked on 2026-11-21. A key for one host is never sent to another.
    public var endpoint: URL {
        switch self {
        case .kimiAI: return URL(string: "https://api.moonshot.ai/v1/chat/completions")!
        case .kimiCN: return URL(string: "https://api.moonshot.cn/v1/chat/completions")!
        case .deepseek: return URL(string: "https://api.deepseek.com/chat/completions")!
        }
    }

    public var model: String {
        switch self {
        case .kimiAI, .kimiCN: return "kimi-k3.1-pro"
        case .deepseek: return "deepseek-flash"
        }
    }

    public var displayName: String {
        switch self {
        case .kimiAI: return "Kimi 国际"
        case .kimiCN: return "Kimi 中国站"
        case .deepseek: return "DeepSeek"
        }
    }
}

public enum AITask: String, Codable, Sendable {
    case columnMapping
    case recordDraft
    case reminderDraft
    case rangeSummary
    case connectionTest
}

public struct AISendPreview: Equatable, Identifiable, Sendable {
    public var id: String { host + task.rawValue + userText }
    public var provider: AIProviderID
    public var host: String
    public var task: AITask
    /// The exact user text that would leave the device. Already redacted.
    public var userText: String
    public var removedBabyNames: Bool

    public init(provider: AIProviderID, task: AITask, userText: String, removedBabyNames: Bool) {
        self.provider = provider
        self.host = provider.endpoint.host ?? ""
        self.task = task
        self.userText = userText
        self.removedBabyNames = removedBabyNames
    }
}

public enum AIRedactor {
    /// Replaces known baby names and keeps at most eight data rows. Notes are replaced with [text].
    public static func mappingSample(headers: [String], rows: [[String]], babyNames: [String], maxRows: Int = 8) -> (text: String, removedNames: Bool) {
        let kept = Array(rows.prefix(maxRows))
        var removed = false
        let body = kept.map { row in
            row.map { cell in redact(cell, names: babyNames, removed: &removed) }.joined(separator: " | ")
        }.joined(separator: "\n")
        let text = "headers: \(headers.joined(separator: " | "))\nrows:\n\(body)"
        return (text, removed)
    }

    public static func redact(_ text: String, names: [String], removed: inout Bool) -> String {
        var result = text
        for name in names where name.count >= 1 {
            if result.localizedCaseInsensitiveContains(name) {
                result = result.replacingOccurrences(of: name, with: "Baby", options: .caseInsensitive)
                removed = true
            }
        }
        return result
    }
}

public struct ColumnMapping: Codable, Equatable, Sendable {
    public var source: String
    public var target: String?
}

public struct RecordDraftSuggestion: Codable, Equatable, Sendable {
    public var kind: String?
    public var start: String?
    public var amountML: Double?
    public var note: String?

    /// A form the person can still edit. Missing times stay empty rather than being invented.
    public func eventDraft() -> EventDraft {
        let kind = EventKind(rawValue: self.kind ?? "") ?? .bottle
        var draft = EventDraft(kind: kind)
        if let start, let date = ISO8601DateFormatter().date(from: start) {
            draft.startDate = date
        }
        if let amountML { draft.amountML = amountML }
        if let note { draft.notes = note }
        return draft
    }
}

public struct ReminderDraftSuggestion: Codable, Equatable, Sendable {
    public var text: String?
    public var minutes: Int?
    public var anchor: String?
}

public struct RangeSummarySuggestion: Codable, Equatable, Sendable {
    public var text: String?
}

public enum AIProposalDecoder {
    public static func columns(from data: Data) throws -> [ColumnMapping] {
        let object = try jsonObject(data)
        guard let rows = object["columns"] as? [[String: Any]] else { throw AIClientError.unreadable }
        return rows.compactMap { row in
            guard let source = row["source"] as? String, !source.isEmpty else { return nil }
            let target = row["target"] as? String
            let known = target.flatMap { StandardImporter.columns.contains($0) ? $0 : nil }
            return ColumnMapping(source: source, target: known)
        }
    }

    public static func record(from data: Data) throws -> RecordDraftSuggestion {
        let object = try jsonObject(data)
        return RecordDraftSuggestion(
            kind: object["kind"] as? String,
            start: object["start"] as? String,
            amountML: object["amountML"] as? Double,
            note: object["note"] as? String
        )
    }

    public static func reminder(from data: Data) throws -> ReminderDraftSuggestion {
        let object = try jsonObject(data)
        return ReminderDraftSuggestion(
            text: object["text"] as? String,
            minutes: object["minutes"] as? Int,
            anchor: object["anchor"] as? String
        )
    }

    public static func summary(from data: Data) throws -> RangeSummarySuggestion {
        RangeSummarySuggestion(text: (try jsonObject(data))["text"] as? String)
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        let trimmed = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { throw AIClientError.unreadable }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: Data(trimmed.utf8))
        } catch {
            throw AIClientError.unreadable
        }
        guard let object = parsed as? [String: Any] else { throw AIClientError.unreadable }
        return object
    }
}

public enum AIClientError: Error, Equatable {
    case unreadable
    case wrongHost
    case http(Int)
}

public enum AIRequestBuilder {
    /// Builds the chat request. `tools` is never set. The token is only the Authorization header.
    public static func request(provider: AIProviderID, userText: String, token: String) -> URLRequest {
        var request = URLRequest(url: provider.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let system = "Return only the JSON object asked for. Do not give medical advice. Do not invent times or amounts. If a value is missing, use null."
        var body: [String: Any] = [
            "model": provider.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userText],
            ],
        ]
        switch provider {
        case .kimiAI, .kimiCN:
            body["response_format"] = ["type": "json_object"]
        case .deepseek:
            body["response_format"] = ["type": "json_object"]
            body["thinking"] = ["type": "disabled"]
            body["max_tokens"] = 800
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    public static func refusesOtherHost(_ request: URLRequest, provider: AIProviderID) -> Bool {
        request.url?.host?.lowercased() != provider.endpoint.host?.lowercased()
    }
}

public protocol AITransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct AIClient {
    public var transport: AITransport

    public init(transport: AITransport) {
        self.transport = transport
    }

    /// Sends only when `approved` is the same preview the person just confirmed.
    public func send(provider: AIProviderID, preview: AISendPreview, token: String, approved: AISendPreview) async throws -> Data {
        guard preview == approved, preview.provider == provider else { throw AIClientError.wrongHost }
        let request = AIRequestBuilder.request(provider: provider, userText: preview.userText, token: token)
        guard !AIRequestBuilder.refusesOtherHost(request, provider: provider) else { throw AIClientError.wrongHost }
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else { throw AIClientError.http(response.statusCode) }
        return data
    }
}
