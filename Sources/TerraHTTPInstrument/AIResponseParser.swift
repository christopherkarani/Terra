import Foundation

struct AIResponseParser {
    static func parse(data: Data) -> ParsedResponse? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let model = json["model"] as? String

        var inputTokens: Int?
        var outputTokens: Int?

        if let usage = json["usage"] as? [String: Any] {
            // OpenAI format
            if let promptTokens = intValue(usage["prompt_tokens"]) {
                inputTokens = promptTokens
            }
            if let completionTokens = intValue(usage["completion_tokens"]) {
                outputTokens = completionTokens
            }

            // Anthropic format (overrides if present, or fills in if OpenAI keys absent)
            if let v = intValue(usage["input_tokens"]) {
                inputTokens = v
            }
            if let v = intValue(usage["output_tokens"]) {
                outputTokens = v
            }
        }

        // Ollama format (top-level keys)
        if let v = intValue(json["prompt_eval_count"]) {
            inputTokens = v
        }
        if let v = intValue(json["eval_count"]) {
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

private func intValue(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber else {
        return nil
    }
    if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return nil
    }
    let double = number.doubleValue
    guard double.isFinite else {
        return nil
    }
    let rounded = double.rounded(.towardZero)
    guard rounded == double else {
        return nil
    }
    let intValue = Int(rounded)
    guard Double(intValue) == rounded else {
        return nil
    }
    return intValue
}

struct ParsedResponse: Sendable {
    let inputTokens: Int?
    let outputTokens: Int?
    let model: String?
}
