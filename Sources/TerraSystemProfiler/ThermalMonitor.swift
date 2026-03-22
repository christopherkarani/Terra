import Foundation
import OpenTelemetryApi

/// A single thermal state measurement at a point in time.
///
/// Use ``ThermalMonitor/sample()`` to capture the current thermal state,
/// or use ``ThermalMonitor/profile(start:end:)`` to compute a full profile
/// over a time window.
public struct ThermalSample: Sendable {
  /// The process thermal state at the time of sampling.
  public let state: ProcessInfo.ThermalState

  /// The wall-clock time when the sample was captured.
  public let timestamp: Date

  /// Creates a new thermal sample.
  ///
  /// - Parameters:
  ///   - state: The `ProcessInfo.ThermalState` at capture time.
  ///   - timestamp: The time of capture. Defaults to `Date()`.
  public init(state: ProcessInfo.ThermalState, timestamp: Date = Date()) {
    self.state = state
    self.timestamp = timestamp
  }
}

/// Aggregated thermal profile over a time window.
///
/// ``ThermalProfile`` records the initial and final thermal states, the peak
/// state reached, total elapsed time, and time spent in a throttled state
/// (serious or critical). Attach to inference traces via ``TelemetryAttributeConvertible``.
///
/// - SeeAlso: ``ThermalMonitor/profile(start:end:)``
public struct ThermalProfile: Sendable, TelemetryAttributeConvertible {
  /// The thermal state at the start of the profiling window.
  public let startState: ProcessInfo.ThermalState

  /// The thermal state at the end of the profiling window.
  public let endState: ProcessInfo.ThermalState

  /// The highest thermal state reached during the window.
  public let peakState: ProcessInfo.ThermalState

  /// Total elapsed time in seconds.
  public let durationSeconds: Double

  /// Time spent in a throttled state (serious or critical), in seconds.
  public let timeInThrottledSeconds: Double

  /// Converts the thermal profile into OpenTelemetry span attributes.
  ///
  /// Produces:
  /// - `terra.thermal.state` (string): Thermal state at end of window.
  /// - `terra.thermal.peak_state` (string): Highest state reached.
  /// - `terra.thermal.time_throttled_s` (double): Seconds spent in throttled state.
  public var telemetryAttributes: [String: AttributeValue] {
    [
      "terra.thermal.state": .string(ThermalMonitor.stateLabel(endState)),
      "terra.thermal.peak_state": .string(ThermalMonitor.stateLabel(peakState)),
      "terra.thermal.time_throttled_s": .double(timeInThrottledSeconds),
    ]
  }
}

/// Monitors the device thermal state and produces thermal profiles.
///
/// Thermal throttling can significantly impact model inference latency. Use
/// ``ThermalMonitor`` to record thermal state transitions and correlate them
/// with inference performance in your traces.
///
/// ## Usage
/// ```swift
/// ThermalMonitor.install()
/// let start = ThermalMonitor.sample()
/// // ... run inference ...
/// let end = ThermalMonitor.sample()
/// let profile = ThermalMonitor.profile(start: start, end: end)
/// ```
public enum ThermalMonitor {
  private static let state = ProfilerInstallState<ThermalMonitor>()

  /// Installs thermal monitoring hooks.
  ///
  /// Call once during app initialization to enable thermal monitoring.
  public static func install() {
    state.install()
  }

  /// Returns `true` if thermal monitoring has been installed.
  public static var isInstalled: Bool {
    state.isInstalled
  }

  /// Captures the current thermal state as a ``ThermalSample``.
  ///
  /// - Returns: A new `ThermalSample` with the current `ProcessInfo.thermalState`
  ///   and the current wall-clock time.
  public static func sample() -> ThermalSample {
    ThermalSample(state: ProcessInfo.processInfo.thermalState)
  }

  /// Returns a human-readable label for a `ProcessInfo.ThermalState`.
  ///
  /// - Parameter state: The thermal state to label.
  /// - Returns: One of `"nominal"`, `"fair"`, `"serious"`, `"critical"`, or `"unknown"`.
  public static func stateLabel(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal: return "nominal"
    case .fair: return "fair"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
  }

  /// Computes a thermal profile between two samples.
  ///
  /// - Parameters:
  ///   - start: The starting ``ThermalSample``.
  ///   - end: The ending ``ThermalSample``.
  /// - Returns: A ``ThermalProfile`` with start/end/peak states, duration, and
  ///   throttled time. Time is considered throttled when either sample is
  ///   `.serious` or `.critical`.
  public static func profile(start: ThermalSample, end: ThermalSample) -> ThermalProfile {
    let peakState = max(start.state.rawValue, end.state.rawValue)
    let duration = end.timestamp.timeIntervalSince(start.timestamp)
    let isThrottled = start.state.rawValue >= ProcessInfo.ThermalState.serious.rawValue
      || end.state.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    let throttledTime = isThrottled ? max(0, duration) : 0

    return ThermalProfile(
      startState: start.state,
      endState: end.state,
      peakState: ProcessInfo.ThermalState(rawValue: peakState) ?? end.state,
      durationSeconds: max(0, duration),
      timeInThrottledSeconds: throttledTime
    )
  }
}
