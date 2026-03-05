import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

/// Span processor that enriches Terra spans with Terra-specific metadata.
package final class TerraSpanEnrichmentProcessor: SpanProcessor {
  package var isStartRequired: Bool { true }
  package var isEndRequired: Bool { false }

  package init() {}

  package func onStart(parentContext: SpanContext?, span: ReadableSpan) {
    guard Terra.SpanNames.isTerraSpanName(span.name) else { return }

    let privacy = Runtime.shared.privacy
    span.setAttribute(key: Terra.Keys.Terra.contentPolicy, value: privacy.contentPolicy.asAttributeValue)
    let redactionValue: AttributeValue
    switch privacy.redaction {
    case .hashHMACSHA256 where !Runtime.isHMACSHA256Available:
      redactionValue = .string("hash_unavailable")
    case .hashSHA256 where !Runtime.isSHA256Available:
      redactionValue = .string("hash_unavailable")
    default:
      redactionValue = privacy.redaction.asAttributeValue
    }
    span.setAttribute(key: Terra.Keys.Terra.contentRedaction, value: redactionValue)
  }

  package func onEnd(span: ReadableSpan) {}
  package func shutdown(explicitTimeout: TimeInterval?) { /* stateless — nothing to flush */ }
  package func forceFlush(timeout: TimeInterval?) { /* stateless — nothing to flush */ }
}

private extension Terra.ContentPolicy {
  var asAttributeValue: AttributeValue {
    switch self {
    case .never:
      return .string("never")
    case .optIn:
      return .string("opt_in")
    case .always:
      return .string("always")
    }
  }
}

private extension Terra.RedactionStrategy {
  var asAttributeValue: AttributeValue {
    switch self {
    case .drop:
      return .string("drop")
    case .lengthOnly:
      return .string("length_only")
    case .hashHMACSHA256:
      if Runtime.isHMACSHA256Available {
        return .string("hash_hmac_sha256")
      } else {
        return .string("hash_unavailable")
      }
    case .hashSHA256:
      if Runtime.isSHA256Available {
        return .string("hash_sha256")
      } else {
        return .string("hash_unavailable")
      }
    }
  }
}
