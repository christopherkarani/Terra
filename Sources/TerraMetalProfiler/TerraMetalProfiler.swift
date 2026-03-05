import Foundation
import OpenTelemetryApi

/// Runtime-toggleable Metal profiling hooks.
///
/// This target intentionally starts as a light wrapper so adopters can opt in
/// without paying overhead until counters are attached.
public enum TerraMetalProfiler {
  private final class InstallState: @unchecked Sendable {
    private let lock = NSLock()
    private var isInstalled = false

    func install() {
      lock.lock()
      isInstalled = true
      lock.unlock()
    }

    func readIsInstalled() -> Bool {
      lock.lock()
      defer { lock.unlock() }
      return isInstalled
    }
  }

  private static let installState = InstallState()

  public static func install() {
    installState.install()
  }

  public static var isInstalled: Bool {
    installState.readIsInstalled()
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
