import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

/// Span processor that enriches Terra spans with Terra-specific metadata.
public final class TerraSpanEnrichmentProcessor: SpanProcessor {
  public var isStartRequired: Bool { true }
  public var isEndRequired: Bool { false }

  public init() {}

  public func onStart(parentContext: SpanContext?, span: ReadableSpan) {
    guard Terra.SpanNames.isTerraSpanName(span.name) else { return }

    let privacy = Runtime.shared.privacy
    let telemetry = Runtime.shared.telemetry
    span.setAttribute(key: Terra.Keys.Terra.contentPolicy, value: privacy.contentPolicy.asAttributeValue)
    span.setAttribute(key: Terra.Keys.Terra.semanticVersion, value: .string(telemetry.semanticVersion.rawValue))
    span.setAttribute(key: Terra.Keys.Terra.schemaFamily, value: .string(telemetry.schemaFamily))
    let redactionValue: AttributeValue
    switch privacy.redaction {
    case .hashSHA256 where !Runtime.isSHA256Available:
      redactionValue = .string("hash_unavailable")
    default:
      redactionValue = privacy.redaction.asAttributeValue
    }
    span.setAttribute(key: Terra.Keys.Terra.contentRedaction, value: redactionValue)
    if let keyID = Runtime.anonymizationKeyID(), !keyID.isEmpty {
      span.setAttribute(key: Terra.Keys.Terra.anonymizationKeyID, value: .string(keyID))
    }
  }

  public func onEnd(span: ReadableSpan) {}
  public func shutdown(explicitTimeout: TimeInterval?) { /* stateless — nothing to flush */ }
  public func forceFlush(timeout: TimeInterval?) { /* stateless — nothing to flush */ }
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
    case .hashSHA256:
      if Runtime.isSHA256Available {
        return .string("hash_sha256")
      } else {
        return .string("hash_unavailable")
      }
    }
  }
}
