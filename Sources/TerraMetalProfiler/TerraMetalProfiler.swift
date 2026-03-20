import Foundation
import OpenTelemetryApi
import TerraSystemProfiler

/// Runtime-toggleable Metal profiling hooks.
///
/// This target intentionally starts as a light wrapper so adopters can opt in
/// without paying overhead until counters are attached.
public enum TerraMetalProfiler {
  private static let state = ProfilerInstallState<TerraMetalProfiler>()

  public static func install() {
    state.install()
  }

  public static var isInstalled: Bool {
    state.isInstalled
  }

  public static func attributes(
    gpuUtilization: Double? = nil,
    memoryInFlightMB: Double? = nil,
    computeTimeMS: Double? = nil
  ) -> [String: AttributeValue] {
    var attributes: [String: AttributeValue] = [:]
    if let gpuUtilization {
      attributes["metal.gpu_utilization"] = .double(gpuUtilization)
    }
    if let memoryInFlightMB {
      attributes["metal.memory_in_flight_mb"] = .double(memoryInFlightMB)
    }
    if let computeTimeMS {
      attributes["metal.compute_time_ms"] = .double(computeTimeMS)
    }
    return attributes
  }
}
