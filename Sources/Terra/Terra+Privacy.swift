import Foundation

extension Terra {
  public enum ContentPolicy: Sendable, Hashable {
    case never
    case optIn
    case always
  }

  public struct AnonymizationPolicy: Sendable, Hashable {
    public var enabled: Bool
    public var keyID: String
    public var secret: String
    public var rotationIntervalSeconds: TimeInterval

    public init(
      enabled: Bool = true,
      keyID: String = "terra-default",
      secret: String = "terra-default-anonymization-secret",
      rotationIntervalSeconds: TimeInterval = 24 * 60 * 60
    ) {
      self.enabled = enabled
      self.keyID = keyID.isEmpty ? "terra-default" : keyID
      self.secret = secret.isEmpty ? "terra-default-anonymization-secret" : secret
      self.rotationIntervalSeconds = rotationIntervalSeconds > 0 ? rotationIntervalSeconds : 24 * 60 * 60
    }

    public static let `default` = AnonymizationPolicy()

    public func keyID(for date: Date = Date()) -> String {
      guard enabled else { return keyID }
      let interval = max(1, Int64(rotationIntervalSeconds))
      let bucket = Int64(date.timeIntervalSince1970) / interval
      return "\(keyID):\(bucket)"
    }

    public func secret(for date: Date = Date()) -> String {
      "\(secret):\(keyID(for: date))"
    }
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
    @available(*, deprecated, renamed: "anonymizationPolicy")
    public var anonymizationKeyID: String?
    public var anonymizationPolicy: AnonymizationPolicy

    public init(
      contentPolicy: ContentPolicy = .never,
      redaction: RedactionStrategy = .hashSHA256,
      anonymizationKeyID: String? = nil,
      anonymizationPolicy: AnonymizationPolicy = .default
    ) {
      self.contentPolicy = contentPolicy
      self.redaction = redaction
      if let anonymizationKeyID, !anonymizationKeyID.isEmpty {
        self.anonymizationKeyID = anonymizationKeyID
        self.anonymizationPolicy = AnonymizationPolicy(
          enabled: anonymizationPolicy.enabled,
          keyID: anonymizationKeyID,
          secret: anonymizationPolicy.secret,
          rotationIntervalSeconds: anonymizationPolicy.rotationIntervalSeconds
        )
      } else {
        self.anonymizationKeyID = nil
        self.anonymizationPolicy = anonymizationPolicy
      }
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
      case (.optIn, .`default`):
        return false
      }
    }
  }

  public struct ExportControlPolicy: Sendable, Hashable {
    public var enabled: Bool
    public var blockOnViolation: Bool
    public var allowedRuntimes: Set<RuntimeKind>

    public init(
      enabled: Bool = true,
      blockOnViolation: Bool = true,
      allowedRuntimes: Set<RuntimeKind> = Set(RuntimeKind.allCases)
    ) {
      self.enabled = enabled
      self.blockOnViolation = blockOnViolation
      self.allowedRuntimes = allowedRuntimes
    }
  }

  public enum RetentionEvictionMode: String, Sendable, Hashable, CaseIterable {
    case lru
    case oldestFirst = "oldest_first"
  }

  public struct RetentionPolicy: Sendable, Hashable {
    public var maxAgeSeconds: TimeInterval
    public var maxLocalBytes: Int
    public var evictionMode: RetentionEvictionMode

    public init(
      maxAgeSeconds: TimeInterval = 7 * 24 * 60 * 60,
      maxLocalBytes: Int = 256 * 1024 * 1024,
      evictionMode: RetentionEvictionMode = .lru
    ) {
      self.maxAgeSeconds = maxAgeSeconds
      self.maxLocalBytes = maxLocalBytes
      self.evictionMode = evictionMode
    }
  }

  public struct AuditEvent: Sendable, Hashable {
    public enum Level: String, Sendable, Hashable, CaseIterable {
      case info
      case warning
      case error
    }

    public var level: Level
    public var message: String
    public var timestamp: Date
    public var attributes: [String: String]

    public init(
      level: Level,
      message: String,
      timestamp: Date = Date(),
      attributes: [String: String] = [:]
    ) {
      self.level = level
      self.message = message
      self.timestamp = timestamp
      self.attributes = attributes
    }
  }

  public struct CompliancePolicy: Sendable, Hashable {
    public var exportControls: ExportControlPolicy
    public var retention: RetentionPolicy
    public var auditEnabled: Bool
    public var crossProcessConsentBoundary: Bool

    public init(
      exportControls: ExportControlPolicy = .init(),
      retention: RetentionPolicy = .init(),
      auditEnabled: Bool = true,
      crossProcessConsentBoundary: Bool = true
    ) {
      self.exportControls = exportControls
      self.retention = retention
      self.auditEnabled = auditEnabled
      self.crossProcessConsentBoundary = crossProcessConsentBoundary
    }

    public static let `default` = CompliancePolicy()
  }
}
