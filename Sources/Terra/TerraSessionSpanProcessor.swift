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
    guard Terra.SpanNames.isTerraSpanName(span.name) else { return }

    let session = sessionManager.getSession()
    span.setAttribute(key: SemanticConventions.Session.id.rawValue, value: session.id)
    if let previousId = session.previousId {
      span.setAttribute(key: SemanticConventions.Session.previousId.rawValue, value: previousId)
    }
  }

  func onEnd(span: ReadableSpan) {}
  func shutdown(explicitTimeout: TimeInterval?) {}
  func forceFlush(timeout: TimeInterval?) {}
}

