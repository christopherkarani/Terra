#if canImport(FoundationModels)
import FoundationModels
import TerraCore
import OpenTelemetryApi

@available(macOS 26.0, iOS 26.0, *)
public final class TerraTracedSession: @unchecked Sendable {
  public enum SessionConcurrencyError: Error, Sendable, Equatable {
    case concurrentOperationNotAllowed
  }

  private actor RequestGate {
    private var inFlight = false

    func enter() throws {
      if inFlight {
        throw SessionConcurrencyError.concurrentOperationNotAllowed
      }
      inFlight = true
    }

    func leave() {
      inFlight = false
    }
  }

  private let session: LanguageModelSession
  public let modelIdentifier: String
  private let requestGate = RequestGate()

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
    try await withExclusiveSessionAccess {
      let request = Terra.InferenceRequest(
        model: modelIdentifier,
        prompt: prompt,
        promptCapture: promptCapture
      )
      let output = try await Terra.withInferenceSpan(request) { scope in
        scope.setAttributes([
          Terra.Keys.Terra.runtime: .string("foundation_models"),
          Terra.Keys.Terra.autoInstrumented: .bool(true)
        ])
        let response = try await session.respond(to: prompt)
        return response.content
      }
      return output
    }
  }

  /// Respond with structured output (@Generable type).
  public func respond<T: Generable>(
    to prompt: String,
    generating type: T.Type,
    promptCapture: Terra.CaptureIntent = .default
  ) async throws -> T {
    try await withExclusiveSessionAccess {
      let request = Terra.InferenceRequest(
        model: modelIdentifier,
        prompt: prompt,
        promptCapture: promptCapture
      )
      let output: T = try await Terra.withInferenceSpan(request) { scope in
        scope.setAttributes([
          Terra.Keys.Terra.runtime: .string("foundation_models"),
          Terra.Keys.Terra.autoInstrumented: .bool(true),
          "terra.foundation_models.response_type": .string(String(describing: T.self))
        ])
        return try await session.respond(to: prompt, generating: type).content
      }
      return output
    }
  }

  /// Stream a response with auto-tracing.
  public func streamResponse(to prompt: String, promptCapture: Terra.CaptureIntent = .default) -> AsyncThrowingStream<String, Error> {
    let modelIdentifier = self.modelIdentifier
    let session = self.session

    return AsyncThrowingStream { continuation in
      let task = Task { [weak self] in
        guard let self else {
          continuation.finish(throwing: CancellationError())
          return
        }

        do {
          try await self.withExclusiveSessionAccess {
            let request = Terra.InferenceRequest(
              model: modelIdentifier,
              prompt: prompt,
              promptCapture: promptCapture,
              stream: true
            )
            try await Terra.withStreamingInferenceSpan(request) { streamScope in
              streamScope.setAttributes([
                Terra.Keys.Terra.runtime: .string("foundation_models"),
                Terra.Keys.Terra.autoInstrumented: .bool(true)
              ])
              let stream = session.streamResponse(to: prompt)
              for try await partial in stream {
                try Task.checkCancellation()
                streamScope.recordChunk()
                if let explicitCount = self.explicitOutputTokenCount(from: partial) {
                  streamScope.recordOutputTokenCount(explicitCount)
                }
                continuation.yield(partial.content)
              }
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

  private func explicitOutputTokenCount(from partial: Any) -> Int? {
    for child in Mirror(reflecting: partial).children {
      guard let label = child.label, Self.supportedTokenCountNames.contains(label) else { continue }
      if let intValue = child.value as? Int, intValue >= 0 {
        return intValue
      }
    }
    return nil
  }

  private func withExclusiveSessionAccess<T>(_ operation: () async throws -> T) async throws -> T {
    try await requestGate.enter()
    do {
      let value = try await operation()
      await requestGate.leave()
      return value
    } catch {
      await requestGate.leave()
      throw error
    }
  }

  func _holdExclusiveAccessForTesting(nanoseconds: UInt64) async throws {
    _ = try await withExclusiveSessionAccess {
      try await Task.sleep(nanoseconds: nanoseconds)
      return ()
    }
  }
}

#else

// Stub so the module always compiles
public enum TerraFoundationModelsPlaceholder {
  // FoundationModels framework not available on this platform/SDK
}

#endif
