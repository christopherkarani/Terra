#if canImport(FoundationModels)
import Foundation
import FoundationModels
import TerraCore
import OpenTelemetryApi

@available(macOS 26.0, iOS 26.0, *)
struct TerraTracedResponse<Content> {
  let content: Content
  let inputTokenCount: Int?
  let outputTokenCount: Int?
  let contextWindowTokens: Int?

  init(
    content: Content,
    inputTokenCount: Int? = nil,
    outputTokenCount: Int? = nil,
    contextWindowTokens: Int? = nil
  ) {
    self.content = content
    self.inputTokenCount = inputTokenCount
    self.outputTokenCount = outputTokenCount
    self.contextWindowTokens = contextWindowTokens
  }

  func attributes() -> [String: AttributeValue] {
    var attributes: [String: AttributeValue] = [:]
    if let inputTokenCount {
      attributes[Terra.Keys.GenAI.usageInputTokens] = .int(inputTokenCount)
    }
    if let outputTokenCount {
      attributes[Terra.Keys.GenAI.usageOutputTokens] = .int(outputTokenCount)
    }
    if let contextWindowTokens {
      attributes[Terra.Keys.Terra.foundationModelsContextWindowTokens] = .int(contextWindowTokens)
    }
    return attributes
  }
}

@available(macOS 26.0, iOS 26.0, *)
struct TerraTracedStreamChunk: Sendable {
  let content: String
  let explicitOutputTokenCount: Int?
}

@available(macOS 26.0, iOS 26.0, *)
protocol TerraTracedSessionBackend {
  func respondText(to prompt: String) async throws -> TerraTracedResponse<String>
  func respondGenerable<T: Generable>(to prompt: String, generating type: T.Type) async throws
    -> TerraTracedResponse<T>
  func streamResponse(to prompt: String) -> AsyncThrowingStream<TerraTracedStreamChunk, Error>
}

@available(macOS 26.0, iOS 26.0, *)
private struct FoundationModelsSessionBackend: TerraTracedSessionBackend {
  private let session: LanguageModelSession

  init(model: SystemLanguageModel, instructions: String?) {
    if let instructions {
      self.session = LanguageModelSession(model: model, instructions: instructions)
    } else {
      self.session = LanguageModelSession(model: model)
    }
  }

  func respondText(to prompt: String) async throws -> TerraTracedResponse<String> {
    let response = try await session.respond(to: prompt)
    let usage = TerraTracedSession.nonStreamUsage(from: response)
    return TerraTracedResponse(
      content: response.content,
      inputTokenCount: usage.inputTokenCount,
      outputTokenCount: usage.outputTokenCount,
      contextWindowTokens: usage.contextWindowTokens
    )
  }

  func respondGenerable<T: Generable>(to prompt: String, generating type: T.Type) async throws
    -> TerraTracedResponse<T>
  {
    let response = try await session.respond(to: prompt, generating: type)
    let usage = TerraTracedSession.nonStreamUsage(from: response)
    return TerraTracedResponse(
      content: response.content,
      inputTokenCount: usage.inputTokenCount,
      outputTokenCount: usage.outputTokenCount,
      contextWindowTokens: usage.contextWindowTokens
    )
  }

  func streamResponse(to prompt: String) -> AsyncThrowingStream<TerraTracedStreamChunk, Error> {
    AsyncThrowingStream { continuation in
      Task {
        do {
          for try await partial in session.streamResponse(to: prompt) {
            continuation.yield(
              TerraTracedStreamChunk(
                content: partial.content,
                explicitOutputTokenCount: TerraTracedSession.explicitOutputTokenCount(from: partial)
              )
            )
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }
}

@available(macOS 26.0, iOS 26.0, *)
public final class TerraTracedSession: @unchecked Sendable {
  private let session: any TerraTracedSessionBackend
  public let modelIdentifier: String

  public init(
    model: SystemLanguageModel = .default,
    instructions: String? = nil,
    modelIdentifier: String = "apple/foundation-model"
  ) {
    self.modelIdentifier = modelIdentifier
    self.session = FoundationModelsSessionBackend(model: model, instructions: instructions)
  }

  init(
    backend: any TerraTracedSessionBackend,
    modelIdentifier: String = "apple/foundation-model"
  ) {
    self.modelIdentifier = modelIdentifier
    self.session = backend
  }

  /// Respond to a prompt with auto-tracing.
  public func respond(to prompt: String, promptCapture: Terra.CaptureIntent = .default) async throws -> String {
    let request = Terra.InferenceRequest(
      model: modelIdentifier,
      prompt: prompt,
      promptCapture: promptCapture
    )
    return try await Terra.withInferenceSpan(request) { scope in
      let response = try await session.respondText(to: prompt)
      var attributes: [String: AttributeValue] = [
        Terra.Keys.Terra.runtime: .string("foundation_models"),
        Terra.Keys.Terra.autoInstrumented: .bool(true)
      ]
      attributes.merge(response.attributes()) { _, new in new }
      scope.setAttributes(attributes)
      return response.content
    }
  }

  /// Respond with structured output (@Generable type).
  public func respond<T: Generable>(
    to prompt: String,
    generating type: T.Type,
    promptCapture: Terra.CaptureIntent = .default
  ) async throws -> T {
    let request = Terra.InferenceRequest(
      model: modelIdentifier,
      prompt: prompt,
      promptCapture: promptCapture
    )
    return try await Terra.withInferenceSpan(request) { scope in
      let response = try await session.respondGenerable(to: prompt, generating: type)
      var attributes: [String: AttributeValue] = [
        Terra.Keys.Terra.runtime: .string("foundation_models"),
        Terra.Keys.Terra.autoInstrumented: .bool(true),
        "terra.foundation_models.response_type": .string(String(describing: T.self))
      ]
      attributes.merge(response.attributes()) { _, new in new }
      scope.setAttributes(attributes)
      return response.content
    }
  }

  /// Stream a response with auto-tracing.
  public func streamResponse(to prompt: String, promptCapture: Terra.CaptureIntent = .default) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      Task {
        let request = Terra.InferenceRequest(
          model: modelIdentifier,
          prompt: prompt,
          promptCapture: promptCapture,
          stream: true
        )
        do {
          try await Terra.withStreamingInferenceSpan(request) { streamScope in
            streamScope.setAttributes([
              Terra.Keys.Terra.runtime: .string("foundation_models"),
              Terra.Keys.Terra.autoInstrumented: .bool(true)
            ])
            let stream = session.streamResponse(to: prompt)
            for try await partial in stream {
              streamScope.recordChunk()
              if let explicitCount = partial.explicitOutputTokenCount {
                streamScope.recordOutputTokenCount(explicitCount)
              }
              continuation.yield(partial.content)
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  static func explicitOutputTokenCount(from partial: Any) -> Int? {
    // Prefer explicit token count values if/when Foundation Models surfaces them.
    firstMatchingNonNegativeInt(
      in: metadataSources(for: partial),
      candidateKeys: [
        "outputtokencount",
        "generatedtokencount",
        "tokencount",
        "tokensgenerated",
      ]
    )
  }

  static func nonStreamUsage(from response: Any) -> (
    inputTokenCount: Int?,
    outputTokenCount: Int?,
    contextWindowTokens: Int?
  ) {
    let sources = metadataSources(for: response)

    let inputTokenCount = firstMatchingNonNegativeInt(
      in: sources,
      candidateKeys: [
        "inputtokencount",
        "prompttokencount",
        "inputtokens",
        "prompttokens",
        "input_tokens",
        "prompt_tokens",
      ]
    )
    let outputTokenCount = firstMatchingNonNegativeInt(
      in: sources,
      candidateKeys: [
        "outputtokencount",
        "generatedtokencount",
        "tokencount",
        "tokensgenerated",
        "completiontokencount",
        "completiontokens",
        "outputtokens",
        "completion_tokens",
        "output_tokens",
      ]
    )
    let contextWindowTokens = firstMatchingNonNegativeInt(
      in: sources,
      candidateKeys: [
        "contextwindowtokens",
        "contextwindow",
        "contextwindowsize",
        "contextlength",
        "maxcontexttokens",
      ]
    )

    return (
      inputTokenCount: inputTokenCount,
      outputTokenCount: outputTokenCount,
      contextWindowTokens: contextWindowTokens
    )
  }

  private static func metadataSources(for value: Any) -> [Any] {
    var sources: [Any] = [value]
    for child in Mirror(reflecting: value).children {
      guard let label = child.label?.lowercased() else { continue }
      switch label {
      case "usage", "tokenusage", "metrics", "statistics":
        sources.append(child.value)
      default:
        continue
      }
    }
    return sources
  }

  private static func firstMatchingNonNegativeInt(in sources: [Any], candidateKeys: Set<String>) -> Int? {
    let normalizedCandidateKeys = Set(candidateKeys.map { $0.lowercased() })
    for source in sources {
      for child in Mirror(reflecting: source).children {
        guard let label = child.label?.lowercased(), normalizedCandidateKeys.contains(label) else { continue }
        if let value = nonNegativeInt(from: child.value) {
          return value
        }
      }
    }
    return nil
  }

  private static func nonNegativeInt(from value: Any) -> Int? {
    guard let unwrapped = unwrapOptional(value) else { return nil }

    if let intValue = unwrapped as? Int, intValue >= 0 {
      return intValue
    }
    if let intValue = unwrapped as? Int64, intValue >= 0, intValue <= Int64(Int.max) {
      return Int(intValue)
    }
    if let intValue = unwrapped as? UInt, intValue <= UInt(Int.max) {
      return Int(intValue)
    }
    if let intValue = unwrapped as? UInt64, intValue <= UInt64(Int.max) {
      return Int(intValue)
    }
    if let number = unwrapped as? NSNumber {
      let doubleValue = number.doubleValue
      if doubleValue >= 0,
         doubleValue.truncatingRemainder(dividingBy: 1) == 0,
         doubleValue <= Double(Int.max)
      {
        return Int(doubleValue)
      }
    }
    if let stringValue = unwrapped as? String,
       let intValue = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
       intValue >= 0
    {
      return intValue
    }
    return nil
  }

  private static func unwrapOptional(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else { return value }
    guard let child = mirror.children.first else { return nil }
    return child.value
  }
}

#else

// Stub so the module always compiles
public enum TerraFoundationModelsPlaceholder {
  // FoundationModels framework not available on this platform/SDK
}

#endif
