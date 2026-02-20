import Foundation

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
}
