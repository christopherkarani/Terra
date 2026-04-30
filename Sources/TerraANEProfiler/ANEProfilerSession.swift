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
  public enum StartResult: String, Sendable, Equatable {
    case startedCollecting = "started_collecting"
    case alreadyActive = "already_active"
    case probeOnly = "probe_only"
    case unavailable
  }

  private static let lock = NSLock()
  private static var active = false

  /// Returns true only while a metric-collection session is active.
  public static var isActive: Bool {
    lock.lock()
    defer { lock.unlock() }
    return active
  }

  /// Starts a new ANE profiling session.
  ///
  /// Resets ANE metrics and begins tracking. Nested calls are ignored while a session
  /// is active.
  public static func start() {
    _ = startWithStatus()
  }

  /// Starts a new ANE profiling session and reports whether metrics can be collected.
  @discardableResult
  public static func startWithStatus() -> StartResult {
    lock.lock()
    defer { lock.unlock() }

    guard !active else { return .alreadyActive }
    switch ANEHardwareProfiler.mode {
    case .collecting:
      break
    case .probeOnly:
      return .probeOnly
    case .unavailable:
      return .unavailable
    }

    terra_ane_reset_metrics()
    active = true
    return .startedCollecting
  }

  /// Stops the current profiling session and returns captured metrics.
  ///
  /// - Returns: ``ANEHardwareMetrics`` with ANE execution time, host overhead, and
  ///   segment count. If no session was active, returns current accumulated metrics.
  public static func stop() -> ANEHardwareMetrics {
    lock.lock()
    defer { lock.unlock() }

    guard active else {
      return ANEHardwareMetrics(from: terra_ane_get_metrics())
    }

    active = false
    return ANEHardwareMetrics(from: terra_ane_get_metrics())
  }
}
