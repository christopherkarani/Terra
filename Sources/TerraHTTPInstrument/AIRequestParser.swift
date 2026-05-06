import Foundation
import os

private let logger = Logger(subsystem: "io.opentelemetry.terra", category: "AIRequestParser")

struct AIRequestParser {
  static let maxBodySizeBytes = 10 * 1_048_576 // 10 MiB

  /// Parse a request body without URL context. Falls through provider shapes
  /// in order: OpenAI/Anthropic top-level → Gemini → Bedrock variants. Models
  /// that live in the URL path (Gemini, Azure deployments, Bedrock model IDs)
  /// require the URL-aware overload below.
  static func parse(body: Data) -> ParsedRequest? {
    parse(body: body, url: nil)
  }

  /// URL-aware parse. The URL is consulted only as a fallback for the model
  /// name when the body lacks a top-level `model` field — Azure OpenAI bodies
  /// omit it (deployment is in the path), Gemini puts the model name in
  /// `/v1*/models/<name>:generateContent`, and Bedrock invoke uses
  /// `/model/<modelId>/invoke[-with-response-stream]`.
  static func parse(body: Data, url: URL?) -> ParsedRequest? {
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

    // Body-shape detection runs in priority order. Each probe inspects only
    // top-level keys before doing any per-element work, so misses are cheap.
    //
    // Order matters: Gemini has a unique `contents` array that must NOT be
    // shadowed by the OpenAI/Anthropic fallback (which would otherwise claim
    // the body as soon as the URL supplies a Gemini model). Bedrock checks
    // come last because their detection depends on the URL, not the body.
    if hasGeminiBodyIndicators(json) {
      if let gemini = parseGeminiShape(json: json, url: url) {
        return gemini
      }
    }
    if hasBedrockBodyIndicators(json: json, url: url) {
      if let bedrock = parseBedrockShape(json: json, url: url) {
        return bedrock
      }
    }
    if let openAIish = parseOpenAIOrAnthropicShape(json: json, url: url) {
      return openAIish
    }

    return nil
  }

  // MARK: - Shape detection probes

  private static func hasGeminiBodyIndicators(_ json: [String: Any]) -> Bool {
    json["contents"] is [[String: Any]] || json["generationConfig"] is [String: Any]
  }

  private static func hasBedrockBodyIndicators(json: [String: Any], url: URL?) -> Bool {
    // A Bedrock body NEVER contains `model` (model is in the URL). The body
    // shape is provider-wrapper specific. We only attempt a Bedrock parse
    // when the URL identifies the route as `/model/<id>/invoke[...]`.
    guard let url, extractBedrockModelID(from: url) != nil else { return false }
    if json["model"] is String { return false }
    return json["max_gen_len"] != nil
      || json["inputText"] is String
      || json["textGenerationConfig"] is [String: Any]
      || json["messages"] is [[String: Any]]
      || json["prompt"] is String
  }

  // MARK: - OpenAI / Anthropic / Ollama / Mistral / Cohere shape

  private static func parseOpenAIOrAnthropicShape(
    json: [String: Any],
    url: URL?
  ) -> ParsedRequest? {
    let model = (json["model"] as? String) ?? extractModelFromURL(url)

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

    let temperature = numericDouble(from: json["temperature"])
    let stream = json["stream"] as? Bool
    let messages = parseOpenAIMessages(from: json["messages"])

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

  // MARK: - Gemini shape

  private static func parseGeminiShape(json: [String: Any], url: URL?) -> ParsedRequest? {
    // Gemini bodies do NOT have `model` (it's in the URL) and NEVER have
    // `messages`. The signal is `contents: [...]` plus an optional
    // `generationConfig: {...}`.
    let contents = json["contents"] as? [[String: Any]]
    let generationConfig = json["generationConfig"] as? [String: Any]
    guard contents != nil || generationConfig != nil else { return nil }

    let model = extractModelFromURL(url)

    var maxTokens: Int?
    var temperature: Double?
    if let cfg = generationConfig {
      if let v = cfg["maxOutputTokens"] as? Int {
        maxTokens = v
      }
      if let v = numericDouble(from: cfg["temperature"]) {
        temperature = v
      }
    }

    // Streaming is signalled by the URL path: `:streamGenerateContent`.
    var stream: Bool?
    if let path = url?.path, path.contains(":streamGenerateContent") {
      stream = true
    }

    let messages = parseGeminiMessages(from: contents ?? [])

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

  private static func parseGeminiMessages(from contents: [[String: Any]]) -> [ParsedMessage] {
    contents.compactMap { entry -> ParsedMessage? in
      let role = (entry["role"] as? String) ?? "user"
      guard let parts = entry["parts"] as? [[String: Any]] else { return nil }
      let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
      guard !text.isEmpty else { return nil }
      return ParsedMessage(role: role, content: text)
    }
  }

  // MARK: - Bedrock shape (per-model wrappers)

  private static func parseBedrockShape(json: [String: Any], url: URL?) -> ParsedRequest? {
    guard let url, let modelID = extractBedrockModelID(from: url) else {
      // No URL means we cannot reliably attribute a Bedrock body shape.
      return nil
    }

    // Streaming is encoded in the URL: `/invoke-with-response-stream`.
    let stream: Bool? = url.path.contains("invoke-with-response-stream") ? true : nil

    // Llama-on-Bedrock: top-level `prompt`, `max_gen_len`.
    if json["max_gen_len"] != nil || (json["prompt"] is String && modelID.lowercased().contains("llama")) {
      let maxTokens = json["max_gen_len"] as? Int
      let temperature = numericDouble(from: json["temperature"])
      return ParsedRequest(
        model: modelID,
        maxTokens: maxTokens,
        temperature: temperature,
        stream: stream,
        messages: []
      )
    }

    // Titan: top-level `inputText`, nested `textGenerationConfig`.
    if json["inputText"] is String || json["textGenerationConfig"] is [String: Any] {
      let cfg = json["textGenerationConfig"] as? [String: Any]
      let maxTokens = cfg?["maxTokenCount"] as? Int
      let temperature = numericDouble(from: cfg?["temperature"])
      return ParsedRequest(
        model: modelID,
        maxTokens: maxTokens,
        temperature: temperature,
        stream: stream,
        messages: []
      )
    }

    // Anthropic-on-Bedrock: same body as native Anthropic but no `model`
    // key (model is in the URL). Detect via `messages` + (optional)
    // `anthropic_version`.
    if json["messages"] is [[String: Any]] {
      let maxTokens = (json["max_tokens"] as? Int)
        ?? (json["max_completion_tokens"] as? Int)
        ?? (json["max_new_tokens"] as? Int)
      let temperature = numericDouble(from: json["temperature"])
      let messages = parseOpenAIMessages(from: json["messages"])
      return ParsedRequest(
        model: modelID,
        maxTokens: maxTokens,
        temperature: temperature,
        stream: stream ?? (json["stream"] as? Bool),
        messages: messages
      )
    }

    return nil
  }

  // MARK: - URL helpers

  /// Extracts the model name from a URL when the provider stashes it in the
  /// path. Supports:
  /// - Azure OpenAI: `/openai/deployments/<deployment>/...`
  /// - Gemini: `/v1*/models/<model>:<verb>`
  /// - Bedrock: `/model/<modelId>/invoke[-with-response-stream]`
  static func extractModelFromURL(_ url: URL?) -> String? {
    guard let url else { return nil }

    if let azure = extractAzureDeploymentName(from: url) { return azure }
    if let gemini = extractGeminiModel(from: url) { return gemini }
    if let bedrock = extractBedrockModelID(from: url) { return bedrock }

    return nil
  }

  private static func extractAzureDeploymentName(from url: URL) -> String? {
    // Match `/openai/deployments/<deployment>/...` regardless of host so we
    // also catch APIM / proxy front-ends that use the same path layout.
    let components = url.pathComponents
    guard let openAIIdx = components.firstIndex(of: "openai"),
          components.indices.contains(openAIIdx + 2),
          components[openAIIdx + 1] == "deployments" else {
      return nil
    }
    let name = components[openAIIdx + 2]
    return name.isEmpty ? nil : name
  }

  private static func extractGeminiModel(from url: URL) -> String? {
    // `/v1beta/models/gemini-1.5-pro:generateContent` →
    // pathComponents == ["/", "v1beta", "models", "gemini-1.5-pro:generateContent"]
    guard let modelsIdx = url.pathComponents.firstIndex(of: "models"),
          url.pathComponents.indices.contains(modelsIdx + 1) else {
      return nil
    }
    let segment = url.pathComponents[modelsIdx + 1]
    // Strip the `:<verb>` (`:generateContent`, `:streamGenerateContent`).
    if let colonIdx = segment.firstIndex(of: ":") {
      return String(segment[..<colonIdx])
    }
    return segment.isEmpty ? nil : segment
  }

  private static func extractBedrockModelID(from url: URL) -> String? {
    // `/model/<modelId>/invoke` — model IDs may contain `:` (URL-encoded as
    // `%3A`). Foundation already decodes percent-encoding when computing
    // pathComponents.
    let components = url.pathComponents
    guard let modelIdx = components.firstIndex(of: "model"),
          components.indices.contains(modelIdx + 1) else {
      return nil
    }
    let id = components[modelIdx + 1]
    return id.isEmpty ? nil : id
  }

  // MARK: - Shared helpers

  private static func parseOpenAIMessages(from value: Any?) -> [ParsedMessage] {
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

  private static func numericDouble(from value: Any?) -> Double? {
    if let v = value as? Double { return v }
    if let v = value as? Int { return Double(v) }
    return nil
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
