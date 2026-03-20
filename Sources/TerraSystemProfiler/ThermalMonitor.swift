import Foundation
import OpenTelemetryApi

public struct ThermalSample: Sendable {
  public let state: ProcessInfo.ThermalState
  public let timestamp: Date

  public init(state: ProcessInfo.ThermalState, timestamp: Date = Date()) {
    self.state = state
    self.timestamp = timestamp
  }
}

public struct ThermalProfile: Sendable, TelemetryAttributeConvertible {
  public let startState: ProcessInfo.ThermalState
  public let endState: ProcessInfo.ThermalState
  public let peakState: ProcessInfo.ThermalState
  public let durationSeconds: Double
  public let timeInThrottledSeconds: Double

  public var telemetryAttributes: [String: AttributeValue] {
    [
      "terra.thermal.state": .string(ThermalMonitor.stateLabel(endState)),
      "terra.thermal.peak_state": .string(ThermalMonitor.stateLabel(peakState)),
      "terra.thermal.time_throttled_s": .double(timeInThrottledSeconds),
    ]
  }
}

public enum ThermalMonitor {
  private static let state = ProfilerInstallState<ThermalMonitor>()

  public static func install() {
    state.install()
  }

  public static var isInstalled: Bool {
    state.isInstalled
  }

  public static func sample() -> ThermalSample {
    ThermalSample(state: ProcessInfo.processInfo.thermalState)
  }

  public static func stateLabel(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal: return "nominal"
    case .fair: return "fair"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
  }

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
