import Foundation
import TerraSystemProfiler
import CTerraANEBridge

/// Hardware profiler for Apple's Neural Engine (ANE).
///
/// The ANE is a dedicated AI accelerator block in Apple silicon that provides
/// significant performance improvements for neural network inference. This profiler
/// captures hardware-level metrics from the ANE including execution time and host
/// overhead.
///
/// - Note: This profiler requires the `TerraANEProfiler` target which uses private
///   Apple APIs. It will not work in App Store distributions.
///
/// Use ``ANEProfilerSession`` to capture metrics over a specific time window, or
/// ``captureMetrics()`` for one-shot metric collection.
public enum ANEHardwareProfiler {
  public enum Mode: String, Sendable, Equatable {
    case unavailable
    case probeOnly = "probe_only"
    case collecting
  }

  private static let state = ProfilerInstallState<ANEHardwareProfiler>()

  /// Returns `true` if ANE hardware is available on this device.
  ///
  /// Check this before attempting to install or capture metrics. ANE hardware
  /// is only present on devices with Apple neural engine (A12 or later).
  public static var isAvailable: Bool {
    terra_ane_is_available()
  }

  /// Returns `true` if the ANE profiler has been installed.
  public static var isInstalled: Bool {
    state.isInstalled
  }

  /// Returns `true` only when Terra has active hooks that collect ANE metrics.
  ///
  /// `isAvailable` means the private probe class exists. This value is stricter:
  /// it remains false until concrete metric-collection swizzling is installed.
  public static var isCollecting: Bool {
    terra_ane_is_collecting()
  }

  /// The current ANE profiler capability mode.
  ///
  /// `probeOnly` means Terra can detect the private ANE probe surface but does
  /// not have metric-collection hooks installed. Treat this as availability
  /// evidence, not measured hardware telemetry.
  public static var mode: Mode {
    if isCollecting { return .collecting }
    if isAvailable { return .probeOnly }
    return .unavailable
  }

  /// Installs the ANE profiling hooks.
  ///
  /// Installs swizzling to intercept ANE-related calls. Probe-only availability
  /// is not treated as installation; ``isCollecting`` is true only when hooks are active.
  ///
  /// - Returns: `true` if metric-collection hooks were installed, `false` if ANE
  ///   is unavailable or the current bridge only supports availability probing.
  @discardableResult
  public static func install() -> Bool {
    guard terra_ane_install_swizzling() else { return false }
    state.install()
    return true
  }

  /// Captures current ANE hardware metrics.
  ///
  /// - Returns: ``ANEHardwareMetrics`` containing ANE execution time, host overhead,
  ///   and segment count.
  public static func captureMetrics() -> ANEHardwareMetrics {
    ANEHardwareMetrics(from: terra_ane_get_metrics())
  }

  /// Resets all ANE metrics to zero.
  ///
  /// Call this before starting a new profiling session to clear historical data.
  public static func reset() {
    terra_ane_reset_metrics()
  }
}
