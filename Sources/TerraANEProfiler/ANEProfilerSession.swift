import Foundation
import CTerraANEBridge

/// Session-based profiler for the Neural Engine.
///
/// ANEProfilerSession provides a scoped interface for ANE profiling. Start a session
/// before running ANE workloads and stop it after to capture aggregated hardware metrics.
///
/// ## Usage
/// ```swift
/// ANEProfilerSession.start()
/// // ... run ANE workloads ...
/// let metrics = ANEProfilerSession.stop()
/// let attrs = metrics.telemetryAttributes
/// ```
public enum ANEProfilerSession {
  private static let lock = NSLock()
  private static var isActive = false

  /// Starts a new ANE profiling session.
  ///
  /// Resets ANE metrics and begins tracking. Nested calls are ignored while a session
  /// is active.
  public static func start() {
    lock.lock()
    defer { lock.unlock() }

    guard !isActive else { return }
    terra_ane_reset_metrics()
    isActive = true
  }

  /// Stops the current profiling session and returns captured metrics.
  ///
  /// - Returns: ``ANEHardwareMetrics`` with ANE execution time, host overhead, and
  ///   segment count. If no session was active, returns current accumulated metrics.
  public static func stop() -> ANEHardwareMetrics {
    lock.lock()
    defer { lock.unlock() }

    guard isActive else {
      return ANEHardwareMetrics(from: terra_ane_get_metrics())
    }

    isActive = false
    return ANEHardwareMetrics(from: terra_ane_get_metrics())
  }
}
