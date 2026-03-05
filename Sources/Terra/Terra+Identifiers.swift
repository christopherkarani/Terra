import Foundation

extension Terra {
  public struct ModelID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
      self.rawValue = value
    }

    public var description: String { rawValue }
  }

  public struct ProviderID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
      self.rawValue = value
    }

    public var description: String { rawValue }
  }

  public struct RuntimeID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
      self.rawValue = value
    }

    public var description: String { rawValue }
  }

  public struct ToolCallID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init() {
      self.rawValue = UUID().uuidString
    }

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
      self.rawValue = value
    }

    public var description: String { rawValue }
  }
}

extension Terra.ModelID: Terra.ScalarValue {
  public var traceScalar: Terra.TraceScalar { .string(rawValue) }
}

extension Terra.ProviderID: Terra.ScalarValue {
  public var traceScalar: Terra.TraceScalar { .string(rawValue) }
}

extension Terra.RuntimeID: Terra.ScalarValue {
  public var traceScalar: Terra.TraceScalar { .string(rawValue) }
}

extension Terra.ToolCallID: Terra.ScalarValue {
  public var traceScalar: Terra.TraceScalar { .string(rawValue) }
}

