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

public final class TerraTracedSession {
  public let modelIdentifier: String

  public init(
    model: SystemLanguageModel = .default,
    instructions: String? = nil,
    modelIdentifier: String = "apple/foundation-model"
  ) {
    _ = model
    _ = instructions
    self.modelIdentifier = modelIdentifier
  }

  public func respond(
    to prompt: String,
    promptCapture: Terra.CapturePolicy = .default
  ) async throws -> String {
    _ = prompt
    _ = promptCapture
    throw TerraFoundationModelsUnavailableError.unavailablePlatform
  }

  public func respond<T: Generable>(
    to prompt: String,
    generating type: T.Type,
    promptCapture: Terra.CapturePolicy = .default
  ) async throws -> T {
    _ = prompt
    _ = type
    _ = promptCapture
    throw TerraFoundationModelsUnavailableError.unavailablePlatform
  }

  public func streamResponse(
    to prompt: String,
    promptCapture: Terra.CapturePolicy = .default
  ) -> AsyncThrowingStream<String, Error> {
    _ = prompt
    _ = promptCapture
    return AsyncThrowingStream { continuation in
      continuation.finish(throwing: TerraFoundationModelsUnavailableError.unavailablePlatform)
    }
  }
}

extension Terra {
  public typealias TracedSession = TerraTracedSession
}
#endif
