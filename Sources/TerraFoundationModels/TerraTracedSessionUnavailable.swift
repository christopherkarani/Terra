#if !canImport(FoundationModels)
import Foundation
import TerraCore

public struct SystemLanguageModel: Sendable, Equatable {
  public static let `default` = Self()
  public init() {}
}

public struct GenerationOptions: Sendable, Equatable {
  public init() {}
}

/// A marker protocol that mirrors `FoundationModels.Generable` on platforms
/// where the FoundationModels framework is unavailable.
///
/// When building for iOS 26+ or macOS 26+, this protocol is replaced by
/// the real `FoundationModels.Generable` conformance. On earlier platforms,
/// types that should be generatable must conform to this stub so that
/// cross-platform code compiles without conditional compilation guards.
public protocol Generable: Sendable {}

public enum TerraFoundationModelsUnavailableError: Error, Sendable {
  case unavailablePlatform
}

extension Terra {
  public final class TracedSession {
    public typealias GuardrailClassifier = @Sendable (any Error) -> String?

    public let modelIdentifier: String

    public init(
      model: SystemLanguageModel = .default,
      instructions: String? = nil,
      modelIdentifier: String = "apple/foundation-model",
      guardrailClassifier: GuardrailClassifier? = nil
    ) {
      _ = model
      _ = instructions
      _ = guardrailClassifier
      self.modelIdentifier = modelIdentifier
    }

    @available(*, deprecated, message: "Use String model identifiers directly.")
    public convenience init(
      model: SystemLanguageModel = .default,
      instructions: String? = nil,
      modelIdentifier: Terra.ModelID,
      guardrailClassifier: GuardrailClassifier? = nil
    ) {
      self.init(
        model: model,
        instructions: instructions,
        modelIdentifier: modelIdentifier.rawValue,
        guardrailClassifier: guardrailClassifier
      )
    }

    public func respond(
      to prompt: String,
      options: GenerationOptions = GenerationOptions(),
      promptCapture: Terra.CapturePolicy = .default
    ) async throws -> String {
      _ = prompt
      _ = options
      _ = promptCapture
      throw TerraFoundationModelsUnavailableError.unavailablePlatform
    }

    public func respond<T: Generable>(
      to prompt: String,
      generating type: T.Type,
      options: GenerationOptions = GenerationOptions(),
      promptCapture: Terra.CapturePolicy = .default
    ) async throws -> T {
      _ = prompt
      _ = type
      _ = options
      _ = promptCapture
      throw TerraFoundationModelsUnavailableError.unavailablePlatform
    }

    public func streamResponse(
      to prompt: String,
      options: GenerationOptions = GenerationOptions(),
      promptCapture: Terra.CapturePolicy = .default
    ) -> AsyncThrowingStream<String, Error> {
      _ = prompt
      _ = options
      _ = promptCapture
      return AsyncThrowingStream { continuation in
        continuation.finish(throwing: TerraFoundationModelsUnavailableError.unavailablePlatform)
      }
    }

    public func streamResponse<T: Sendable>(
      to prompt: String,
      options: GenerationOptions = GenerationOptions(),
      promptCapture: Terra.CapturePolicy = .default,
      transform: @escaping @Sendable (String) throws -> T
    ) -> AsyncThrowingStream<T, Error> {
      _ = prompt
      _ = options
      _ = promptCapture
      _ = transform
      return AsyncThrowingStream { continuation in
        continuation.finish(throwing: TerraFoundationModelsUnavailableError.unavailablePlatform)
      }
    }
  }
}
#endif
