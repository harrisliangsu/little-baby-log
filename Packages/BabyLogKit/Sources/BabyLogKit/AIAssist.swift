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

    /// The provider's default model. A chosen model is resolved separately so one vendor's ID cannot ride on another.
    public var model: String { AIModelCatalog.defaultID(for: self) }

    public var displayName: String {
        switch self {
        case .kimiAI: return "Kimi 国际"
        case .kimiCN: return "Kimi 中国站"
        case .deepseek: return "DeepSeek"
        }
    }
}

public struct AIModelChoice: Equatable, Identifiable, Sendable {
    public var id: String { rawID }
    public var rawID: String
    public var title: String

    public init(rawID: String, title: String) {
        self.rawID = rawID
        self.title = title
    }
}

/// Official model IDs checked on 2026-11-22. The app does not fetch this list or accept a typed name.
public enum AIModelCatalog {
    public static func choices(for provider: AIProviderID) -> [AIModelChoice] {
        switch provider {
        case .deepseek:
            return [
                AIModelChoice(rawID: "deepseek-flash", title: "Flash"),
                AIModelChoice(rawID: "deepseek-v4-pro", title: "V4 Pro"),
            ]
        case .kimiAI, .kimiCN:
            return [
                AIModelChoice(rawID: "kimi-k3.1-pro", title: "K3.1 Pro"),
                AIModelChoice(rawID: "kimi-k3.1-pro-highspeed", title: "K3.1 Pro 高速"),
                AIModelChoice(rawID: "kimi-k3", title: "K3"),
            ]
        }
    }

    public static func defaultID(for provider: AIProviderID) -> String {
        choices(for: provider)[0].rawID
    }

    /// Unknown IDs, including another provider's model, become this provider's default.
    public static func resolve(_ stored: String?, for provider: AIProviderID) -> String {
        let known = choices(for: provider).map(\.rawID)
        if let stored, known.contains(stored) { return stored }
        return defaultID(for: provider)
    }
}

/// Per-provider model memory. Selecting a model for one provider does not change the others.
public struct AIModelSelection: Equatable, Sendable {
    public var byProvider: [String: String]

    public init(byProvider: [String: String] = [:]) {
        self.byProvider = byProvider
    }

    public func current(for provider: AIProviderID) -> String {
        AIModelCatalog.resolve(byProvider[provider.rawValue], for: provider)
    }

    public func choosing(_ rawID: String, for provider: AIProviderID) -> AIModelSelection {
        var copy = self
        copy.byProvider[provider.rawValue] = AIModelCatalog.resolve(rawID, for: provider)
        return copy
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
    /// Chat replies arrive as `choices[0].message.content`. Tests and a raw JSON body stay as they are.
    public static func modelJSON(from data: Data) throws -> Data {
        let trimmed = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let root = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) else {
            throw AIClientError.unreadable
        }
        if let object = root as? [String: Any],
           let choices = object["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            let inner = stripFences(content)
            guard !inner.isEmpty else { throw AIClientError.unreadable }
            return Data(inner.utf8)
        }
        return Data(trimmed.utf8)
    }

    public static func payload(from data: Data) throws -> [String: Any] {
        try jsonObject(try modelJSON(from: data))
    }

    public static func columns(from data: Data) throws -> [ColumnMapping] {
        let object = try payload(from: data)
        guard let rows = object["columns"] as? [[String: Any]] else { throw AIClientError.unreadable }
        return rows.compactMap { row in
            guard let source = row["source"] as? String, !source.isEmpty else { return nil }
            let target = row["target"] as? String
            let known = target.flatMap { StandardImporter.columns.contains($0) ? $0 : nil }
            return ColumnMapping(source: source, target: known)
        }
    }

    public static func record(from data: Data) throws -> RecordDraftSuggestion {
        let object = try payload(from: data)
        return RecordDraftSuggestion(
            kind: object["kind"] as? String,
            start: object["start"] as? String,
            amountML: object["amountML"] as? Double,
            note: object["note"] as? String
        )
    }

    public static func reminder(from data: Data) throws -> ReminderDraftSuggestion {
        let object = try payload(from: data)
        return ReminderDraftSuggestion(
            text: object["text"] as? String,
            minutes: object["minutes"] as? Int,
            anchor: object["anchor"] as? String
        )
    }

    public static func summary(from data: Data) throws -> RangeSummarySuggestion {
        RangeSummarySuggestion(text: (try payload(from: data))["text"] as? String)
    }

    private static func stripFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```") {
            if let firstNewline = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: firstNewline)...])
            }
            if result.hasSuffix("```") {
                result.removeLast(3)
            }
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
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
    case cancelled
}

public enum AIRequestBuilder {
    /// Builds the chat request. `tools` is never set. The token is only the Authorization header.
    public static func request(provider: AIProviderID, model explicit: String? = nil, userText: String, token: String) -> URLRequest {
        var request = URLRequest(url: provider.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let system = "Return only the JSON object asked for. Do not give medical advice. Do not invent times or amounts. If a value is missing, use null."
        var body: [String: Any] = [
            "model": AIModelCatalog.resolve(explicit, for: provider),
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
    /// `access` and `flight` are the master switch: a closed switch or a cancelled ticket never reaches the network,
    /// and a ticket cancelled while the request is out drops the body instead of returning it.
    public func send(
        provider: AIProviderID,
        preview: AISendPreview,
        token: String,
        approved: AISendPreview,
        model: String? = nil,
        access: AIAccess = .ready,
        flight: AIFlight? = nil,
        ticket: Int = 0
    ) async throws -> Data {
        guard preview == approved, preview.provider == provider else { throw AIClientError.wrongHost }
        guard AISendGuard.shouldSend(access: access, flight: flight, ticket: ticket) else { throw AIClientError.cancelled }
        let request = AIRequestBuilder.request(provider: provider, model: model, userText: preview.userText, token: token)
        guard !AIRequestBuilder.refusesOtherHost(request, provider: provider) else { throw AIClientError.wrongHost }
        let (data, response) = try await transport.data(for: request)
        guard AISendGuard.shouldSend(access: access, flight: flight, ticket: ticket) else { throw AIClientError.cancelled }
        guard (200..<300).contains(response.statusCode) else { throw AIClientError.http(response.statusCode) }
        return data
    }
}
