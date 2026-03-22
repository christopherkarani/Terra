import Foundation

extension Terra {
  /// A unique identifier for a GenAI model (e.g., 'gpt-4o-mini', 'claude-3-sonnet').
  ///
  /// `ModelID` wraps a string value provided by the AI provider. Terra uses this
  /// identifier to attribute telemetry to the specific model that handled an inference
  /// request, making it easy to filter traces and metrics by model in dashboards.
  ///
  /// - Note: Model IDs are provider-specific strings and are not validated by Terra.
  ///   An invalid or unknown model ID will not prevent tracing — it simply means
  ///   the model name appears as-is in telemetry.
  public struct ModelID: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
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
  /// telemetry correctly when the same `ModelID` may run on multiple backends.
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

  /// A unique identifier for a tool call within an agentic workflow.
  ///
  /// `ToolCallID` is generated as a UUID when a tool is invoked by an agent,
  /// and is attached to the resulting trace span. This lets you correlate
  /// tool calls across the full agentic loop — from the model's decision to
  /// invoke a tool through to the tool's execution and the model's response.
  ///
  /// Terra generates a UUID by default, but you can also provide a custom
  /// identifier when the calling context already has a meaningful ID.
  public struct ToolCallID: Codable, Hashable, Sendable {
    public let rawValue: String

    /// Creates a new `ToolCallID` with a randomly generated UUID.
    public init() {
      self.rawValue = UUID().uuidString
    }

    /// Creates a new `ToolCallID` with the given string value.
    ///
    /// Use this initializer when you already have a stable identifier from
    /// the calling system (e.g., a request ID or conversation ID).
    ///
    /// - Parameter rawValue: A string identifier for this tool call.
    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }
  }
}

extension Terra.ModelID: Terra.ScalarValue {
  package var traceScalar: Terra.TraceScalar { .string(rawValue) }
}

extension Terra.ProviderID: Terra.ScalarValue {
  package var traceScalar: Terra.TraceScalar { .string(rawValue) }
}

extension Terra.RuntimeID: Terra.ScalarValue {
  package var traceScalar: Terra.TraceScalar { .string(rawValue) }
}

extension Terra.ToolCallID: Terra.ScalarValue {
  package var traceScalar: Terra.TraceScalar { .string(rawValue) }
}
