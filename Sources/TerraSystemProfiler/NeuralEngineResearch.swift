import Foundation
import OpenTelemetryApi

/// Research-mode hooks for experimental ANE instrumentation.
///
/// ``NeuralEngineResearch`` provides a gated probe for future ANE telemetry features.
/// All research-mode functionality is disabled by default and requires the
/// `TERRA_EXPERIMENTAL_ANE_PROBE=1` environment variable to be set.
///
/// - Warning: This is experimental and subject to change without notice.
///   Do not use in production code.
public enum NeuralEngineResearch {
  /// Returns `true` if the experimental ANE probe is enabled.
  ///
  /// Check this before calling ``probeSummary()`` or ``coreMLAttributes()``.
  /// The probe is enabled by setting `TERRA_EXPERIMENTAL_ANE_PROBE=1` in the process environment.
  public static var isExperimentalProbeEnabled: Bool {
    ProcessInfo.processInfo.environment["TERRA_EXPERIMENTAL_ANE_PROBE"] == "1"
  }

  /// Returns a human-readable summary of the ANE probe state.
  ///
  /// - Returns: `"ANE probe enabled (research mode)"` if enabled, otherwise
  ///   `"ANE probe disabled"`.
  public static func probeSummary() -> String {
    guard isExperimentalProbeEnabled else {
      return "ANE probe disabled"
    }
    return "ANE probe enabled (research mode)"
  }

  /// Returns CoreML-related attributes from the experimental ANE probe.
  ///
  /// - Warning: Experimental. Returns an empty dictionary when disabled.
  ///
  /// - Returns: CoreML telemetry attributes when the probe is enabled,
  ///   or an empty dictionary when disabled.
  package static func coreMLAttributes() -> [String: AttributeValue] {
    guard isExperimentalProbeEnabled else { return [:] }
    // Experimental probe is reserved for future instrumentation.
    return [:]
  }
}
