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
    let modelIdentifier = self.modelIdentifier
    let session = self.session

    return AsyncThrowingStream { continuation in
      let task = Task { [weak self] in
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
              try Task.checkCancellation()
              streamScope.recordChunk()
              if let explicitCount = self?.explicitOutputTokenCount(from: partial) {
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
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private static let supportedTokenCountNames: Set<String> = [
    "outputTokenCount",
    "generatedTokenCount",
    "tokenCount",
    "tokensGenerated",
  ]

  /// Tracks whether we've already probed for a token count field and found none.
  private var tokenCountFieldChecked = false

  private func explicitOutputTokenCount(from partial: Any) -> Int? {
    // After first nil result, skip Mirror reflection entirely
    if tokenCountFieldChecked { return nil }

    for child in Mirror(reflecting: partial).children {
      guard let label = child.label, Self.supportedTokenCountNames.contains(label) else { continue }
      if let intValue = child.value as? Int, intValue >= 0 {
        return intValue
      }
    }
    tokenCountFieldChecked = true
    return nil
  }
}

#else

// Stub so the module always compiles
public enum TerraFoundationModelsPlaceholder {
  // FoundationModels framework not available on this platform/SDK
}

#endif
