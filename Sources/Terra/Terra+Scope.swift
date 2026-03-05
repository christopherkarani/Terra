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
  final class Scope<Kind>: @unchecked Sendable {
    private let underlyingSpan: any Span

    init(span: any Span) {
      underlyingSpan = span
    }

    /// Advanced escape hatch for integrations that already depend on OpenTelemetry APIs.
    var span: any Span { underlyingSpan }

    func addEvent(_ name: String, attributes: [String: AttributeValue] = [:]) {
      if attributes.isEmpty {
        underlyingSpan.addEvent(name: name)
      } else {
        underlyingSpan.addEvent(name: name, attributes: attributes)
      }
    }

    func recordError(_ error: any Error, captureMessage: Bool? = nil) {
      let message = String(describing: error)
      let exceptionType = String(reflecting: type(of: error))
      let shouldCaptureMessage = captureMessage ?? Runtime.shared.privacy.shouldCapture(includeContent: false)
      underlyingSpan.status = .error(description: shouldCaptureMessage ? message : exceptionType)

      var attributes: [String: AttributeValue] = [
        "exception.type": .string(exceptionType),
      ]
      if shouldCaptureMessage {
        attributes["exception.message"] = .string(message)
      }

      underlyingSpan.addEvent(
        name: "exception",
        attributes: attributes,
        timestamp: Date()
      )
    }

    func setAttributes(_ attributes: [String: AttributeValue]) {
      underlyingSpan.setAttributes(attributes)
    }
  }
}
