import Foundation
import OpenTelemetryApi

public enum NeuralEngineResearch {
  public static var isExperimentalProbeEnabled: Bool {
    ProcessInfo.processInfo.environment["TERRA_EXPERIMENTAL_ANE_PROBE"] == "1"
  }

  public static func probeSummary() -> String {
    guard isExperimentalProbeEnabled else {
      return "ANE probe disabled"
    }
    return "ANE probe enabled (research mode)"
  }

  /// Returns CoreML-related attributes from experimental ANE probe.
  /// Returns an empty dictionary when the probe is disabled.
  package static func coreMLAttributes() -> [String: AttributeValue] {
    guard isExperimentalProbeEnabled else { return [:] }
    // Experimental probe is reserved for future instrumentation.
    return [:]
  }
}
