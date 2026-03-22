import Foundation

extension Terra {
  /// Error type thrown by Terra operations.
  ///
  /// `TerraError` is a structured error type with a deterministic `code`, a human-readable
  /// `message`, an optional `context` dictionary with additional details (endpoint URLs,
  /// configuration keys, state transitions), and an optional `underlying` error.
  ///
  /// All error codes are stable and deterministic, making them safe to handle in code:
  ///
  /// ```swift
  /// do {
  ///     try await Terra.start(myConfig)
  /// } catch let error as Terra.TerraError {
  ///     switch error.code {
  ///     case .already_started:
  ///         try await Terra.reconfigure(myConfig)
  ///     case .invalid_endpoint:
  ///         print("Fix your endpoint URL:", error.context)
  ///     default:
  ///         throw error
  ///     }
  /// }
  /// ```
  ///
  /// - SeeAlso: `TerraError.Code` for all available error codes.
  public struct TerraError: Error, Sendable, Equatable, Hashable, LocalizedError {
    /// Structured error codes for Terra-specific error conditions.
    ///
    /// Each code represents a distinct failure mode that can be handled programmatically.
    /// Codes are stable — Terra will never reuse a code for a different error condition.
    public struct Code: Sendable, Hashable {
      public let rawValue: String

      public init(_ rawValue: String) {
        self.rawValue = rawValue
      }

      /// The `Destination.endpoint` URL is invalid (not http/https or missing host).
      ///
      /// Remediation: Provide a valid OTLP endpoint URL, then retry `Terra.start()` or `Terra.reconfigure()`.
      public static let invalid_endpoint = Self("invalid_endpoint")

      /// Failed to initialize persistence storage at the configured URL.
      ///
      /// Common causes: directory does not exist, not writable, or disk is full.
      /// Remediation: Ensure `persistence` URL points to a writable directory, then retry.
      public static let persistence_setup_failed = Self("persistence_setup_failed")

      /// `Terra.start()` was called but Terra is already running.
      ///
      /// Remediation: Call `Terra.reconfigure(...)` for live configuration updates,
      /// or call `Terra.shutdown()` / `Terra.reset()` before starting again.
      public static let already_started = Self("already_started")

      /// The requested lifecycle transition is not valid for the current state.
      ///
      /// Example: calling `Terra.reconfigure()` when Terra is not running.
      /// Remediation: Call lifecycle APIs only from valid states; see `Terra.lifecycleState`.
      public static let invalid_lifecycle_state = Self("invalid_lifecycle_state")

      /// Terra failed to start for an unspecified reason.
      ///
      /// Check `TerraError.context` for details (endpoint, storage URL) and
      /// `TerraError.underlying` for the root cause.
      public static let start_failed = Self("start_failed")

      /// Terra failed to reconfigure.
      ///
      /// The reconfigure operation performs a shutdown then a fresh start.
      /// If the start phase fails, this code is returned.
      /// Check `TerraError.context` and `TerraError.underlying` for details.
      public static let reconfigure_failed = Self("reconfigure_failed")
    }

    /// Wraps an underlying error from the system or a dependency.
    ///
    /// Contains the concrete Swift error type name and its string description,
    /// making it possible to log or introspect the root cause while maintaining
    /// a stable, structured error surface.
    public struct Underlying: Sendable, Equatable, Hashable {
      public let type: String
      public let message: String

      init(type: String, message: String) {
        self.type = type
        self.message = message
      }

      /// Creates an `Underlying` from any `Error`.
      init(error: any Error) {
        type = String(reflecting: Swift.type(of: error))
        message = String(describing: error)
      }
    }

    /// The error code identifying the type of failure.
    public let code: Code

    /// A human-readable message describing the error.
    public let message: String

    /// Additional context about the error (endpoint URL, configuration keys, state transition).
    ///
    /// The exact keys depend on the error code. For example, `.invalid_endpoint`
    /// includes `"endpoint": "<url>"`; `.invalid_lifecycle_state` includes
    /// `"transition": "<name>"` and `"state": "<current state>"`.
    public let context: [String: String]

    /// The underlying system or dependency error that caused this `TerraError`, if any.
    public let underlying: Underlying?

    /// Creates a `TerraError` with the given code, message, context, and optional underlying error.
    ///
    /// - Parameters:
    ///   - code: The error code identifying the failure mode.
    ///   - message: A human-readable description of what went wrong.
    ///   - context: Additional key-value pairs with diagnostic information. Defaults to empty.
    ///   - underlying: The root cause error from a system framework or dependency, if available.
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

    /// Returns the error message — conforms to `LocalizedError`.
    public var errorDescription: String? { message }

    /// A human-readable hint for resolving the error.
    ///
    /// Use this to provide actionable remediation guidance to developers
    /// in error UIs or logs.
    public var remediationHint: String {
      code.remediationHint
    }
  }
}

extension Terra.TerraError.Code {
  /// A human-readable hint for resolving the error associated with this code.
  ///
  /// Each code maps to a specific remediation string that provides actionable
  /// guidance (e.g., which configuration to fix, which API to call instead).
  /// Use `TerraError.remediationHint` to access this from a `TerraError` instance.
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
