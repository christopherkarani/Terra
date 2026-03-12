import Foundation

extension Terra {
  public struct ModelID: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }
  }

  public struct ProviderID: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }
  }

  public struct RuntimeID: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }
  }

  public struct ToolCallID: Codable, Hashable, Sendable {
    public let rawValue: String

    public init() {
      self.rawValue = UUID().uuidString
    }

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
