import Foundation
import OpenTelemetryApi

extension Terra {
  /// A lightweight helper passed to `Terra.with*Span` bodies.
  ///
  /// This is intentionally small and misuse-resistant: it exposes common operations without requiring
  /// callers to learn OpenTelemetry internals.
  // @unchecked Sendable: `underlyingSpan` is an immutable (`let`) reference. All mutations
  // (addEvent, setAttribute, status) delegate to the OTel SDK Span, which serializes access
  // through its own internal lock — no additional synchronization is needed here.
  public final class Scope<Kind>: @unchecked Sendable {
    private let underlyingSpan: any Span

    init(span: any Span) {
      underlyingSpan = span
    }

    /// Advanced escape hatch for integrations that already depend on OpenTelemetry APIs.
    public var span: any Span { underlyingSpan }

    public func addEvent(_ name: String, attributes: [String: AttributeValue] = [:]) {
      if attributes.isEmpty {
        underlyingSpan.addEvent(name: name)
      } else {
        underlyingSpan.addEvent(name: name, attributes: attributes)
      }
    }

    public func recordError(_ error: any Error, captureMessage: Bool = true) {
      let message = String(describing: error)
      let exceptionType = String(reflecting: type(of: error))
      underlyingSpan.status = .error(description: exceptionType)

      var attributes: [String: AttributeValue] = [
        "exception.type": .string(exceptionType),
      ]
      if captureMessage {
        attributes.merge(redactedErrorAttributes(message: message, privacy: Runtime.shared.privacy)) { _, new in new }
      }

      underlyingSpan.addEvent(
        name: "exception",
        attributes: attributes,
        timestamp: Date()
      )
    }

    public func setAttributes(_ attributes: [String: AttributeValue]) {
      underlyingSpan.setAttributes(attributes)
    }
  }
}

private func redactedErrorAttributes(message: String, privacy: Terra.Privacy) -> [String: AttributeValue] {
  switch privacy.redaction {
  case .drop:
    return [:]
  case .lengthOnly:
    return [Terra.Keys.Terra.errorMessageLength: .int(message.count)]
  case .hashHMACSHA256:
    var attributes: [String: AttributeValue] = [
      Terra.Keys.Terra.errorMessageLength: .int(message.count),
    ]
    if Runtime.isHMACSHA256Available, let digest = Runtime.shared.hmacSHA256Hex(message) {
      attributes[Terra.Keys.Terra.errorMessageHMACSHA256] = .string(digest)
      if let keyID = Runtime.shared.anonymizationKeyIDValue {
        attributes[Terra.Keys.Terra.anonymizationKeyID] = .string(keyID)
      }
    }
    if privacy.emitLegacySHA256Attributes, Runtime.isSHA256Available, let legacyDigest = Runtime.sha256Hex(message) {
      attributes[Terra.Keys.Terra.errorMessageSHA256] = .string(legacyDigest)
    }
    return attributes
  case .hashSHA256:
    var attributes: [String: AttributeValue] = [
      Terra.Keys.Terra.errorMessageLength: .int(message.count),
    ]
    if Runtime.isSHA256Available, let digest = Runtime.sha256Hex(message) {
      attributes[Terra.Keys.Terra.errorMessageSHA256] = .string(digest)
    }
    return attributes
  }
}
