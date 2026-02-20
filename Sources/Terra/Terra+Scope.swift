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

    public func recordError(_ error: any Error) {
      let message = String(describing: error)
      underlyingSpan.status = .error(description: message)
      underlyingSpan.addEvent(
        name: "exception",
        attributes: [
          "exception.message": .string(message),
          "exception.type": .string(String(reflecting: type(of: error))),
        ],
        timestamp: Date()
      )
    }

    public func setAttributes(_ attributes: [String: AttributeValue]) {
      underlyingSpan.setAttributes(attributes)
    }
  }
}

