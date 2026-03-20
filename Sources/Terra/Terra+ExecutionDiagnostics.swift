import OpenTelemetryApi
import TerraSystemProfiler

extension Terra {
  package enum ExecutionRouteCaptureMode: String, Sendable {
    case runtimeObserved = "runtime_observed"
    case planEstimated = "plan_estimated"
    case heuristic = "heuristic"
    case experimentalProbe = "experimental_probe"
  }

  package enum ExecutionRouteConfidence: String, Sendable {
    case high
    case medium
    case low
  }

  package struct ExecutionRouteEvidence: Sendable, TelemetryAttributeConvertible {
    package var requested: String?
    package var observed: String?
    package var estimatedPrimary: String?
    package var supported: [String]
    package var captureMode: ExecutionRouteCaptureMode?
    package var confidence: ExecutionRouteConfidence?

    package init(
      requested: String? = nil,
      observed: String? = nil,
      estimatedPrimary: String? = nil,
      supported: [String] = [],
      captureMode: ExecutionRouteCaptureMode? = nil,
      confidence: ExecutionRouteConfidence? = nil
    ) {
      self.requested = requested
      self.observed = observed
      self.estimatedPrimary = estimatedPrimary
      self.supported = supported
      self.captureMode = captureMode
      self.confidence = confidence
    }

    package var telemetryAttributes: [String: AttributeValue] {
      var attributes: [String: AttributeValue] = [:]
      if let requested {
        attributes[Keys.Terra.execRouteRequested] = .string(requested)
      }
      if let observed {
        attributes[Keys.Terra.execRouteObserved] = .string(observed)
      }
      if let estimatedPrimary {
        attributes[Keys.Terra.execRouteEstimatedPrimary] = .string(estimatedPrimary)
      }
      if !supported.isEmpty {
        attributes[Keys.Terra.execRouteSupported] = .string(supported.joined(separator: ","))
      }
      if let captureMode {
        attributes[Keys.Terra.execRouteCaptureMode] = .string(captureMode.rawValue)
      }
      if let confidence {
        attributes[Keys.Terra.execRouteConfidence] = .string(confidence.rawValue)
      }
      return attributes
    }
  }
}
