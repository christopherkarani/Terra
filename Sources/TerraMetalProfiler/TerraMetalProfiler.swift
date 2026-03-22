import Foundation
import OpenTelemetryApi
import TerraSystemProfiler

/// Runtime-toggleable Metal profiler hooks.
///
/// TerraMetalProfiler provides a lightweight profiling interface for Metal GPU workloads.
/// This target starts as a light wrapper so adopters can opt in without paying overhead
/// until counters are attached.
///
/// The profiler generates OpenTelemetry attributes for GPU utilization, memory in flight,
/// and compute time. Attach these to your inference traces for correlated performance data.
///
/// ```swift
/// // Install profiler
/// TerraMetalProfiler.install()
///
/// // Capture GPU metrics during inference
/// let attrs = TerraMetalProfiler.attributes(
///     gpuUtilization: 0.85,
///     memoryInFlightMB: 256.0,
///     computeTimeMS: 12.5
/// )
/// ```
public enum TerraMetalProfiler {
  private static let state = ProfilerInstallState<TerraMetalProfiler>()

  /// Installs the Metal profiling hooks.
  ///
  /// Call this once during your app's initialization phase before any Metal
  /// compute operations you want to profile.
  public static func install() {
    state.install()
  }

  /// Returns `true` if the Metal profiler has been installed.
  public static var isInstalled: Bool {
    state.isInstalled
  }

  /// Creates a dictionary of Metal-related telemetry attributes.
  ///
  /// - Parameters:
  ///   - gpuUtilization: GPU utilization as a fraction (0.0 to 1.0).
  ///   - memoryInFlightMB: Amount of Metal memory currently in use in megabytes.
  ///   - computeTimeMS: GPU compute kernel execution time in milliseconds.
  ///
  /// - Returns: Dictionary of attribute key-value pairs for telemetry.
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
