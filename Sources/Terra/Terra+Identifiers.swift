import Foundation

extension Terra {
  /// Identifies a model using a string-backed compatibility wrapper.
  ///
  /// New code should pass model names as plain `String`, but `ModelID` remains
  /// available so existing integrations can migrate without immediate source edits.
  @available(*, deprecated, message: "Use String model names directly.")
  public struct ModelID: Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
      self.rawValue = value
    }
  }

  /// Identifies a tool call using a string-backed compatibility wrapper.
  ///
  /// New code should pass tool call IDs as plain `String`, but `ToolCallID` remains
  /// available for one compatibility cycle so existing call sites keep compiling.
  @available(*, deprecated, message: "Use String tool call identifiers directly.")
  public struct ToolCallID: Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    /// Creates a compatibility call ID using the legacy auto-generated behavior.
    ///
    /// Keep this initializer during the deprecation window so older call sites and
    /// default arguments continue compiling while migrating to raw strings.
    public init() {
      self.rawValue = UUID().uuidString
    }

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
      self.rawValue = value
    }
  }

  /// Identifies the AI provider (e.g., OpenAI, Anthropic, Google) that handles inference.
  ///
  /// `ProviderID` is a string identifier used in OpenTelemetry spans and metrics to
  /// attribute telemetry to the upstream provider. This lets you compare latency,
  /// token usage, and error rates across different providers in a single dashboard.
  ///
  /// - SeeAlso: [OpenTelemetry semantic conventions for GenAI](https://opentelemetry.io/docs/specs/semconv/gen-ai/)
  public struct ProviderID: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }
  }

  /// Identifies the runtime backend used for model execution (e.g., `http_api`, `coreml`, `mlx`, `ane`).
  ///
  /// `RuntimeID` describes the execution environment of a model, distinguishing between
  /// cloud API calls and on-device inference runtimes. This is critical for attributing
  /// telemetry correctly when the same model name may run on multiple backends.
  ///
  /// Common runtime identifiers:
  /// - `http_api` — Cloud API calls to a remote provider
  /// - `coreml` — Apple's CoreML on-device inference
  /// - `mlx` — MLX framework (Apple Silicon)
  /// - `ane` — Apple Neural Engine (via private APIs; non-App-Store)
  public struct RuntimeID: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }
  }
}

extension Terra.ModelID: Terra.ScalarValue {
  package var traceScalar: Terra.TraceScalar { .string(rawValue) }
}

extension Terra.ToolCallID: Terra.ScalarValue {
  package var traceScalar: Terra.TraceScalar { .string(rawValue) }
}

extension Terra.ProviderID: Terra.ScalarValue {
  package var traceScalar: Terra.TraceScalar { .string(rawValue) }
}

extension Terra.RuntimeID: Terra.ScalarValue {
  package var traceScalar: Terra.TraceScalar { .string(rawValue) }
}
