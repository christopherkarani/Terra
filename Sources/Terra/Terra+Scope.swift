import Foundation
import OpenTelemetryApi

extension Terra {
  /// A lightweight helper passed to `Terra.with*Span` bodies.
  ///
  /// This is intentionally small and misuse-resistant: it exposes common operations without requiring
  /// callers to learn OpenTelemetry internals.
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

    public func recordError(_ error: any Error) {
      let message = String(describing: error)
      let errorType = String(reflecting: type(of: error))

      var attributes: [String: AttributeValue] = [
        "exception.type": .string(errorType)
      ]

      let privacy = Runtime.shared.privacy
      if privacy.contentPolicy == .always {
        switch privacy.redaction {
        case .drop:
          break
        case .lengthOnly:
          attributes[Terra.Keys.Terra.errorMessageLength] = .int(message.count)
        case .hashSHA256:
          attributes[Terra.Keys.Terra.errorMessageLength] = .int(message.count)
          if Runtime.isSHA256Available, let hash = Runtime.sha256Hex(message) {
            attributes[Terra.Keys.Terra.errorMessageSHA256] = .string(hash)
          }
        }
      }

      // Keep status description non-sensitive unless explicit message capture is supported.
      underlyingSpan.status = .error(description: errorType)
      underlyingSpan.addEvent(name: "exception", attributes: attributes, timestamp: Date())
    }

    public func setAttributes(_ attributes: [String: AttributeValue]) {
      underlyingSpan.setAttributes(attributes)
    }
  }
}
