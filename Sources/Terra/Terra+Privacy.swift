import Foundation

extension Terra {
  public enum ContentPolicy: Sendable, Hashable {
    case never
    case optIn
    case always
  }

  public enum CaptureIntent: Sendable, Hashable {
    case `default`
    case optIn
  }

  public enum RedactionStrategy: Sendable, Hashable {
    case drop
    case lengthOnly
    case hashSHA256
  }

  public struct Privacy: Sendable, Hashable {
    public var contentPolicy: ContentPolicy
    public var redaction: RedactionStrategy

    public init(contentPolicy: ContentPolicy = .never, redaction: RedactionStrategy = .hashSHA256) {
      self.contentPolicy = contentPolicy
      self.redaction = redaction
    }

    public static let `default` = Privacy()

    func shouldCapture(promptCapture: CaptureIntent) -> Bool {
      switch (contentPolicy, promptCapture) {
      case (.never, _):
        return false
      case (.always, _):
        return true
      case (.optIn, .optIn):
        return true
      case (.optIn, .default):
        return false
      }
    }
  }
}

