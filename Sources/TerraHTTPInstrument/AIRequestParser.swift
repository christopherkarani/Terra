import Foundation
import os

private let logger = Logger(subsystem: "io.opentelemetry.terra", category: "AIRequestParser")

struct AIRequestParser {
    static let maxBodySizeBytes = 10 * 1_048_576 // 10 MiB

    static func parse(body: Data) -> ParsedRequest? {
        guard body.count <= maxBodySizeBytes else {
            logger.debug("Request body exceeds max size: \(body.count) bytes")
            return nil
        }

        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return nil
            }
            json = parsed
        } catch {
            logger.debug("Failed to parse request JSON: \(error.localizedDescription)")
            return nil
        }

        let model = json["model"] as? String

        let maxTokens: Int?
        if let v = json["max_tokens"] as? Int {
            maxTokens = v
        } else if let v = json["max_completion_tokens"] as? Int {
            maxTokens = v
        } else if let v = json["max_new_tokens"] as? Int {
            maxTokens = v
        } else {
            maxTokens = nil
        }

        let temperature: Double?
        if let v = json["temperature"] as? Double {
            temperature = v
        } else if let v = json["temperature"] as? Int {
            temperature = Double(v)
        } else {
            temperature = nil
        }

        let stream = json["stream"] as? Bool

        let messages = parseMessages(from: json["messages"])

        guard model != nil || maxTokens != nil || temperature != nil || stream != nil || !messages.isEmpty else {
            return nil
        }

        return ParsedRequest(
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            stream: stream,
            messages: messages
        )
    }

    private static func parseMessages(from value: Any?) -> [ParsedMessage] {
        guard let rawMessages = value as? [[String: Any]] else { return [] }
        return rawMessages.compactMap { message in
            guard let role = message["role"] as? String else { return nil }
            guard let content = extractContent(from: message["content"]), !content.isEmpty else { return nil }
            return ParsedMessage(role: role, content: content)
        }
    }

    private static func extractContent(from value: Any?) -> String? {
        if let content = value as? String {
            return content
        }
        guard let parts = value as? [[String: Any]] else { return nil }

        let text = parts.compactMap { part -> String? in
            if let type = part["type"] as? String, type == "text", let value = part["text"] as? String {
                return value
            }
            if let type = part["type"] as? String, type == "input_text", let value = part["text"] as? String {
                return value
            }
            return nil
        }
        .joined(separator: "\n")

        return text.isEmpty ? nil : text
    }
}

struct ParsedRequest: Sendable {
    let model: String?
    let maxTokens: Int?
    let temperature: Double?
    let stream: Bool?
    let messages: [ParsedMessage]
}

struct ParsedMessage: Sendable, Equatable {
    let role: String
    let content: String
}
