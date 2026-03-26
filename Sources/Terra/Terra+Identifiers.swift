import Foundation

extension Terra {
  /// Identifies the AI provider (for example `openai`, `anthropic`, or `mlx`).
  public struct ProviderID: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }
  }

  /// Identifies the runtime backend used for execution (for example `http_api`, `coreml`, or `mlx`).
  public struct RuntimeID: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }
  }
}

extension Terra.ProviderID: Terra.ScalarValue {
  package var traceScalar: Terra.TraceScalar { .string(rawValue) }
}

extension Terra.RuntimeID: Terra.ScalarValue {
  package var traceScalar: Terra.TraceScalar { .string(rawValue) }
}
