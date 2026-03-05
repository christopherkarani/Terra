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
  }
}
