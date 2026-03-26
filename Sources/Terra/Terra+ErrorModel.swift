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

      /// Terra rejected a usage pattern and is returning guidance toward the correct API.
      ///
      /// Use this when an operation is structurally invalid rather than transport- or
      /// lifecycle-failed, for example when code tries to mutate an ended span handle.
      public static let guidance = Self("guidance")

      /// Terra detected that the caller chose a closure-scoped API for a multi-step agentic workflow.
      public static let wrong_api_for_agentic = Self("wrong_api_for_agentic")

      /// Terra detected that trace context was dropped across an async boundary and can point to the supported fix.
      public static let context_not_propagated = Self("context_not_propagated")

      /// Terra detected configuration that is syntactically valid but incomplete for the requested workflow.
      ///
      /// Use this for actionable setup problems where the SDK can point callers to the
      /// exact fix, such as a missing exporter endpoint or missing provider registration.
      public static let misconfiguration = Self("misconfiguration")

      /// Terra rejected an API sequence that cannot succeed in the current state.
      ///
      /// Use this when the call shape is wrong rather than the runtime configuration,
      /// for example reusing an ended trace builder or mutating an ended span handle.
      public static let invalid_operation = Self("invalid_operation")
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

    /// A human-readable recovery suggestion derived from the error code or explicit context.
    ///
    /// Prefer this when rendering developer-facing diagnostics because it preserves
    /// Terra's structured remediation while allowing more specific guidance for
    /// individual failures through the `"fix"` or `"recovery_suggestion"` context keys.
    public var recoverySuggestion: String {
      context["recovery_suggestion"] ?? context["fix"] ?? remediationHint
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
    case Terra.TerraError.Code.guidance.rawValue:
      return "Follow the guidance message and prefer Terra.trace(...) or Terra.startSpan(...) for explicit lifecycle workflows."
    case Terra.TerraError.Code.wrong_api_for_agentic.rawValue:
      return "Use Terra.agentic(...) or explicitly bind child work with .under(parentSpan) when the workflow spans multiple steps."
    case Terra.TerraError.Code.context_not_propagated.rawValue:
      return "Use SpanHandle.detached(...) or AgentHandle.detached(...) instead of raw Task.detached when parent trace linkage matters."
    case Terra.TerraError.Code.misconfiguration.rawValue:
      return "Apply the suggested Terra configuration fix, then rerun Terra.diagnose() to verify the setup."
    case Terra.TerraError.Code.invalid_operation.rawValue:
      return "Adjust the Terra API sequence to the suggested pattern and retry the operation."
    default:
      return "Inspect TerraError.context and TerraError.underlying, then retry with corrected configuration/state."
    }
  }
}

extension Terra.TerraError {
  static func guidance(_ message: String, context: [String: String] = [:]) -> Self {
    Self(code: .guidance, message: message, context: context)
  }

  /// Creates a guidance error that teaches the correct Terra API with a copy-paste example.
  ///
  /// Use this when the caller chose a structurally wrong pattern. The resulting error is
  /// optimized for coding agents and humans because it explains why the call failed,
  /// which API should replace it, and includes a complete example in the payload.
  public static func guidance(
    message: String,
    why: String,
    correctAPI: String,
    example: String,
    context: [String: String] = [:]
  ) -> Self {
    var merged = context
    merged["why"] = why
    merged["correct_api"] = correctAPI
    merged["example"] = example
    merged["recovery_suggestion"] = "Use \(correctAPI)."
    return Self(
      code: .guidance,
      message: """
      \(message)

      Why this pattern does not work:
      \(why)

      Use this API instead:
      \(correctAPI)

      Example:
      \(example)
      """,
      context: merged
    )
  }

  /// Creates a guidance error for choosing a closure-scoped API where an agentic root span is required.
  public static func wrongAPIForAgentic(
    usedAPI: String,
    suggestedAPI: String,
    why: String,
    example: String
  ) -> Self {
    let message = """
    \(usedAPI) is the wrong Terra entry point for this agentic workflow.

    Why this pattern does not work:
    \(why)

    Use this API instead:
    \(suggestedAPI)

    Example:
    \(example)
    """

    return Self(
      code: .wrong_api_for_agentic,
      message: message,
      context: [
        "used_api": usedAPI,
        "correct_api": suggestedAPI,
        "why": why,
        "example": example,
        "recovery_suggestion": "Use \(suggestedAPI).",
      ]
    )
  }

  /// Creates a guidance error for trace context that was dropped across an async boundary.
  public static func contextNotPropagated(reason: String, fix: String) -> Self {
    Self(
      code: .context_not_propagated,
      message: """
      Terra could not keep the active trace context attached to this work.

      Reason:
      \(reason)

      Fix:
      \(fix)
      """,
      context: [
        "reason": reason,
        "fix": fix,
        "recovery_suggestion": fix,
      ]
    )
  }

  /// Creates a misconfiguration error with a stable remediation payload.
  public static func misconfiguration(
    code: String,
    message: String,
    fix: String,
    context: [String: String] = [:]
  ) -> Self {
    var merged = context
    merged["configuration_code"] = code
    merged["fix"] = fix
    return Self(code: .misconfiguration, message: message, context: merged)
  }

  /// Creates an invalid-operation error with concrete recovery guidance.
  public static func invalidOperation(
    reason: String,
    correctAPI: String? = nil,
    example: String? = nil,
    context: [String: String] = [:]
  ) -> Self {
    var merged = context
    if let correctAPI {
      merged["correct_api"] = correctAPI
    }
    if let example {
      merged["example"] = example
    }
    if let correctAPI {
      merged["recovery_suggestion"] = "Use \(correctAPI)."
    }
    return Self(code: .invalid_operation, message: reason, context: merged)
  }
}
