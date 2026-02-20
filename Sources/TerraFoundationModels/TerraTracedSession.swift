#if canImport(FoundationModels)
import FoundationModels
import TerraCore
import OpenTelemetryApi

@available(macOS 26.0, iOS 26.0, *)
public final class TerraTracedSession: @unchecked Sendable {
  private let session: LanguageModelSession
  public let modelIdentifier: String

  public init(
    model: SystemLanguageModel = .default,
    instructions: String? = nil,
    modelIdentifier: String = "apple/foundation-model"
  ) {
    self.modelIdentifier = modelIdentifier
    if let instructions {
      self.session = LanguageModelSession(model: model, instructions: instructions)
    } else {
      self.session = LanguageModelSession(model: model)
    }
  }

  /// Respond to a prompt with auto-tracing.
  public func respond(to prompt: String, promptCapture: Terra.CaptureIntent = .default) async throws -> String {
    let request = Terra.InferenceRequest(
      model: modelIdentifier,
      prompt: prompt,
      promptCapture: promptCapture
    )
    return try await Terra.withInferenceSpan(request) { scope in
      scope.setAttributes([
        Terra.Keys.Terra.runtime: .string("foundation_models"),
        Terra.Keys.Terra.autoInstrumented: .bool(true)
      ])
      let response = try await session.respond(to: prompt)
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
      scope.setAttributes([
        Terra.Keys.Terra.runtime: .string("foundation_models"),
        Terra.Keys.Terra.autoInstrumented: .bool(true),
        "terra.foundation_models.response_type": .string(String(describing: T.self))
      ])
      return try await session.respond(to: prompt, generating: type).content
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
              if let explicitCount = explicitOutputTokenCount(from: partial) {
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

  private func explicitOutputTokenCount(from partial: Any) -> Int? {
    // Prefer explicit token count values if/when Foundation Models surfaces them.
    let supportedNames: Set<String> = [
      "outputTokenCount",
      "generatedTokenCount",
      "tokenCount",
      "tokensGenerated",
    ]

    for child in Mirror(reflecting: partial).children {
      guard let label = child.label, supportedNames.contains(label) else { continue }
      if let intValue = child.value as? Int, intValue >= 0 {
        return intValue
      }
    }
    return nil
  }
}

#else

// Stub so the module always compiles
public enum TerraFoundationModelsPlaceholder {
  // FoundationModels framework not available on this platform/SDK
}

#endif
