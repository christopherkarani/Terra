extension Terra {
  public enum PrivacyPolicy: String, Sendable, Hashable {
    case redacted
    case lengthOnly
    case capturing
    case silent

    public var shouldCapture: Bool { self == .capturing }

    public func shouldCapture(includeContent: Bool) -> Bool {
      if self == .silent { return false }
      return includeContent || self == .capturing
    }

    package var redactionStrategy: RedactionStrategy {
      switch self {
      case .redacted:
        return .hashHMACSHA256
      case .lengthOnly:
        return .lengthOnly
      case .capturing:
        return .hashHMACSHA256
      case .silent:
        return .drop
      }
    }
  }
}
