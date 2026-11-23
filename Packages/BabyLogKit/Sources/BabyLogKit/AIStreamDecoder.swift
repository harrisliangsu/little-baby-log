import Foundation

/// Turns one HTTP body into text the chat can show. OpenAI-style SSE is assembled here.
/// A normal JSON completion is left intact for the existing decoder.
/// This is not the DeepSeek web demo and does not speak its Anthropic messages protocol.
public enum AIStreamDecoder {
    public static func assembledText(from data: Data, contentType: String?) -> String? {
        let raw = String(decoding: data, as: UTF8.self)
        let type = contentType?.lowercased() ?? ""
        if type.contains("text/event-stream") || raw.contains("\ndata:") || raw.hasPrefix("data:") {
            let text = events(in: raw).compactMap(deltaText(in:)).joined()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    /// WHATWG event-stream blocks. Comment lines are ignored. `data: [DONE]` ends the stream.
    static func events(in text: String) -> [String] {
        var events: [String] = []
        var data = ""
        var hasData = false
        for line in text.components(separatedBy: .newlines) {
            let row = String(line)
            if row.isEmpty {
                if hasData {
                    events.append(data)
                    data = ""
                    hasData = false
                }
                continue
            }
            if row.hasPrefix(":") { continue }
            let field: String
            let value: String
            if let colon = row.firstIndex(of: ":") {
                field = String(row[..<colon])
                var rest = String(row[row.index(after: colon)...])
                if rest.hasPrefix(" ") { rest.removeFirst() }
                value = rest
            } else {
                field = row
                value = ""
            }
            guard field == "data" else { continue }
            if value == "[DONE]" { break }
            data = hasData ? data + "\n" + value : value
            hasData = true
        }
        if hasData { events.append(data) }
        return events
    }

    static func deltaText(in event: String) -> String? {
        guard let data = event.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let choice = choices.first else { return nil }
        if let delta = choice["delta"] as? [String: Any], let text = delta["content"] as? String {
            return text
        }
        if let message = choice["message"] as? [String: Any], let text = message["content"] as? String {
            return text
        }
        return nil
    }
}

/// Separates words the person can read from a record payload. Raw JSON is not shown.
public enum ChatSurface {
    public static func present(_ raw: String) -> (text: String, records: Data?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["items"] != nil || object["text"] != nil {
            let text = (object["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (sanitize(text), data)
        }
        if let start = trimmed.range(of: "<records>"), let end = trimmed.range(of: "</records>") {
            let json = String(trimmed[start.upperBound..<end.lowerBound])
            let prose = String(trimmed[..<start.lowerBound]) + String(trimmed[end.upperBound...])
            return (sanitize(prose), json.data(using: .utf8))
        }
        return (sanitize(trimmed), nil)
    }

    public static func sanitize(_ text: String) -> String {
        var result = text
        let hidden = ["JSON", "json", "schema", "解析助手"]
        for word in hidden where result.contains(word) && result.count < 80 {
            return ""
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
