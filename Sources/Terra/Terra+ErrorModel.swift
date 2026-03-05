import Foundation

extension Terra {
  public struct TerraError: Error, Sendable, Equatable, Hashable, LocalizedError {
    public struct Code: Sendable, Hashable {
      public let rawValue: String

      public init(_ rawValue: String) {
        self.rawValue = rawValue
      }

      public static let invalid_endpoint = Self("invalid_endpoint")
      public static let persistence_setup_failed = Self("persistence_setup_failed")
      public static let already_started = Self("already_started")
      public static let invalid_lifecycle_state = Self("invalid_lifecycle_state")
      public static let start_failed = Self("start_failed")
      public static let reconfigure_failed = Self("reconfigure_failed")
    }

    public struct Underlying: Sendable, Equatable, Hashable {
      public let type: String
      public let message: String

      init(type: String, message: String) {
        self.type = type
        self.message = message
      }

      init(error: any Error) {
        type = String(reflecting: Swift.type(of: error))
        message = String(describing: error)
      }
    }

    public let code: Code
    public let message: String
    public let context: [String: String]
    public let underlying: Underlying?

    public init(
      code: Code,
      message: String,
      context: [String: String] = [:],
      underlying: (any Error)? = nil
    ) {
      self.code = code
      self.message = message
      self.context = context
      self.underlying = underlying.map(Underlying.init(error:))
    }

    public var errorDescription: String? { message }

    public var remediationHint: String {
      code.remediationHint
    }
  }
}

extension Terra.TerraError.Code {
  public var remediationHint: String {
    switch rawValue {
    case Terra.TerraError.Code.invalid_endpoint.rawValue:
      return "Use a valid OTLP endpoint URL (http/https + host), then retry start/reconfigure."
    case Terra.TerraError.Code.persistence_setup_failed.rawValue:
      return "Ensure persistence.storageURL points to a writable directory, then retry start/reconfigure."
    case Terra.TerraError.Code.already_started.rawValue:
      return "Use Terra.reconfigure(...) for live updates, or call Terra.shutdown()/reset() before starting again."
    case Terra.TerraError.Code.invalid_lifecycle_state.rawValue:
      return "Call lifecycle APIs only from valid states (for example: start before reconfigure/shutdown)."
    case Terra.TerraError.Code.start_failed.rawValue:
      return "Check TerraError.context and exporter/runtime configuration, then retry Terra.start()."
    case Terra.TerraError.Code.reconfigure_failed.rawValue:
      return "Check TerraError.context and configuration deltas, then retry Terra.reconfigure(...)."
    default:
      return "Inspect TerraError.context and TerraError.underlying, then retry with corrected configuration/state."
    }
  }
}
