import Foundation
import os

private let logger = Logger(subsystem: "io.opentelemetry.terra", category: "AIResponseParser")

struct AIResponseParser {
  static func parse(data: Data) -> ParsedResponse? {
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

    // Response model can live under either `model` (OpenAI/Anthropic/Ollama)
    // or `modelVersion` (Gemini). Both are optional.
    let model = (json["model"] as? String) ?? (json["modelVersion"] as? String)

    var inputTokens: Int?
    var outputTokens: Int?

    // OpenAI / Anthropic / Bedrock-Anthropic — all wrap usage under `usage`.
    if let usage = json["usage"] as? [String: Any] {
      // OpenAI: snake_case prompt/completion tokens.
      if let v = usage["prompt_tokens"] as? Int {
        inputTokens = v
      }
      if let v = usage["completion_tokens"] as? Int {
        outputTokens = v
      }

      // Anthropic native: snake_case input/output tokens. Overrides OpenAI
      // keys when both are present (matches existing precedence).
      if let v = usage["input_tokens"] as? Int {
        inputTokens = v
      }
      if let v = usage["output_tokens"] as? Int {
        outputTokens = v
      }

      // Bedrock-Anthropic: camelCase (`inputTokens`/`outputTokens`).
      if let v = usage["inputTokens"] as? Int {
        inputTokens = v
      }
      if let v = usage["outputTokens"] as? Int {
        outputTokens = v
      }
    }

    // Gemini — `usageMetadata.{promptTokenCount, candidatesTokenCount}`.
    if let usageMeta = json["usageMetadata"] as? [String: Any] {
      if let v = usageMeta["promptTokenCount"] as? Int {
        inputTokens = v
      }
      if let v = usageMeta["candidatesTokenCount"] as? Int {
        outputTokens = v
      }
    }

    // Cohere — `meta.tokens.{input_tokens, output_tokens}`.
    if let meta = json["meta"] as? [String: Any],
       let tokens = meta["tokens"] as? [String: Any] {
      if let v = tokens["input_tokens"] as? Int {
        inputTokens = v
      }
      if let v = tokens["output_tokens"] as? Int {
        outputTokens = v
      }
    }

    // Bedrock-Titan — top-level `inputTextTokenCount`,
    // `results[0].tokenCount`.
    if let v = json["inputTextTokenCount"] as? Int {
      inputTokens = v
    }
    if let results = json["results"] as? [[String: Any]],
       let first = results.first,
       let v = first["tokenCount"] as? Int {
      outputTokens = v
    }

    // Bedrock-Llama — top-level snake_case counts.
    if let v = json["prompt_token_count"] as? Int {
      inputTokens = v
    }
    if let v = json["generation_token_count"] as? Int {
      outputTokens = v
    }

    // Ollama — top-level `prompt_eval_count` / `eval_count`. Kept last so
    // existing Ollama precedence is preserved.
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
