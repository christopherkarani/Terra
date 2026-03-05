import Foundation

extension Terra {
  package enum ContentPolicy: Sendable, Hashable {
    case never
    case optIn
    case always
  }

  package enum CaptureIntent: Sendable, Hashable {
    case `default`
    case optIn
  }

  package enum RedactionStrategy: Sendable, Hashable {
    case drop
    case lengthOnly
    case hashHMACSHA256
    /// Legacy deterministic hash mode kept for compatibility.
    case hashSHA256
  }

  package struct Privacy: Sendable, Hashable {
    package var contentPolicy: ContentPolicy
    package var redaction: RedactionStrategy
    package var anonymizationKey: Data?
    package var emitLegacySHA256Attributes: Bool

    package init(
      contentPolicy: ContentPolicy = .never,
      redaction: RedactionStrategy = .hashHMACSHA256,
      anonymizationKey: Data? = nil,
      emitLegacySHA256Attributes: Bool = false
    ) {
      self.contentPolicy = contentPolicy
      self.redaction = redaction
      self.anonymizationKey = anonymizationKey
      self.emitLegacySHA256Attributes = emitLegacySHA256Attributes
    }

    package static let `default` = Privacy()

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
