import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import Sessions

/// Adds session context to Terra spans without globally affecting all spans in the host app.
final class TerraSessionSpanProcessor: SpanProcessor {
  var isStartRequired: Bool { true }
  var isEndRequired: Bool { false }

  private let sessionManager: SessionManager

  init(sessionManager: SessionManager? = nil) {
    self.sessionManager = sessionManager ?? SessionManagerProvider.getInstance()
  }

  func onStart(parentContext: SpanContext?, span: ReadableSpan) {
    // Filter broadened (P1-7): match by tracer scope first so user-named
    // workflow spans (e.g. `Terra.workflow(name: "request-workflow")`) still
    // receive session metadata, then fall back to the canonical span-name
    // allowlist for spans produced by upstream Terra integrations that may
    // borrow a foreign tracer.
    guard Self.isTerraOwnedSpan(span) else { return }

    let session = sessionManager.getSession()
    span.setAttribute(key: SemanticConventions.Session.id.rawValue, value: session.id)
    if let previousId = session.previousId {
      span.setAttribute(key: SemanticConventions.Session.previousId.rawValue, value: previousId)
    }
  }

  private static func isTerraOwnedSpan(_ span: ReadableSpan) -> Bool {
    if span.instrumentationScopeInfo.name == Terra.instrumentationName {
      return true
    }
    return Terra.SpanNames.isTerraSpanName(span.name)
  }

  func onEnd(span: ReadableSpan) {}
  func shutdown(explicitTimeout: TimeInterval?) { /* stateless — nothing to flush */ }
  func forceFlush(timeout: TimeInterval?) { /* stateless — nothing to flush */ }
}

