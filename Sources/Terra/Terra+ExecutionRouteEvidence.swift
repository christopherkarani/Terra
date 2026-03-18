import OpenTelemetryApi

extension Terra {
  package enum ExecutionRouteCaptureMode: String, Sendable, Hashable {
    case requestedOnly = "requested_only"
    case sampledObserved = "sampled_observed"
    case explicitObserved = "explicit_observed"
  }

  package enum ExecutionRouteConfidence: String, Sendable, Hashable {
    case low
    case medium
    case high
  }

  package struct ExecutionRouteEvidence: Sendable, Hashable {
    package let requested: String
    package let observed: String?
    package let estimatedPrimary: String?
    package let supported: [String]
    package let captureMode: ExecutionRouteCaptureMode
    package let confidence: ExecutionRouteConfidence

    package init(
      requested: String,
      observed: String? = nil,
      estimatedPrimary: String? = nil,
      supported: [String] = [],
      captureMode: ExecutionRouteCaptureMode,
      confidence: ExecutionRouteConfidence
    ) {
      self.requested = requested
      self.observed = observed
      self.estimatedPrimary = estimatedPrimary
      self.supported = supported
      self.captureMode = captureMode
      self.confidence = confidence
    }

    package var attributes: [String: AttributeValue] {
      var attributes: [String: AttributeValue] = [
        Keys.Terra.execRouteRequested: .string(requested),
        Keys.Terra.execRouteCaptureMode: .string(captureMode.rawValue),
        Keys.Terra.execRouteConfidence: .string(confidence.rawValue),
      ]

      if let observed {
        attributes[Keys.Terra.execRouteObserved] = .string(observed)
      }
      if let estimatedPrimary {
        attributes[Keys.Terra.execRouteEstimatedPrimary] = .string(estimatedPrimary)
      }
      if !supported.isEmpty {
        attributes[Keys.Terra.execRouteSupported] = .string(supported.joined(separator: ","))
      }

      return attributes
    }
  }
}
