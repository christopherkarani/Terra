import Foundation
import os

private let logger = Logger(subsystem: "io.opentelemetry.terra", category: "AIResponseParser")

struct AIResponseParser {
    static let maxBodySizeBytes = 10 * 1_048_576 // 10 MiB

    static func parse(data: Data) -> ParsedResponse? {
        guard data.count <= maxBodySizeBytes else {
            logger.debug("Response body exceeds max size: \(data.count) bytes")
            return nil
        }

        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            json = parsed
        } catch {
            logger.debug("Failed to parse response JSON: \(error.localizedDescription)")
            return nil
        }

        let model = json["model"] as? String

        var inputTokens: Int?
        var outputTokens: Int?

        if let usage = json["usage"] as? [String: Any] {
            // OpenAI format
            if let promptTokens = usage["prompt_tokens"] as? Int {
                inputTokens = promptTokens
            }
            if let completionTokens = usage["completion_tokens"] as? Int {
                outputTokens = completionTokens
            }

            // Anthropic format (overrides if present, or fills in if OpenAI keys absent)
            if let v = usage["input_tokens"] as? Int {
                inputTokens = v
            }
            if let v = usage["output_tokens"] as? Int {
                outputTokens = v
            }
        }

        // Ollama format (top-level keys)
        if let v = json["prompt_eval_count"] as? Int {
            inputTokens = v
        }
        if let v = json["eval_count"] as? Int {
            outputTokens = v
        }

        guard model != nil || inputTokens != nil || outputTokens != nil else {
            return nil
        }

        return ParsedResponse(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            model: model
        )
    }
}

struct ParsedResponse: Sendable {
    let inputTokens: Int?
    let outputTokens: Int?
    let model: String?
}
