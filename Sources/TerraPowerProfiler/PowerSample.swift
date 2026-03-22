import Foundation
import OpenTelemetryApi
import TerraSystemProfiler

/// A single power measurement sample from `powermetrics`.
///
/// Contains instantaneous power readings for CPU, GPU, ANE, and total package
/// consumption in watts.
public struct PowerSample: Sendable, Codable, Hashable {
  /// CPU power consumption in watts.
  public let cpuWatts: Double

  /// GPU power consumption in watts.
  public let gpuWatts: Double

  /// ANE power consumption in watts.
  public let aneWatts: Double

  /// Total package power consumption in watts.
  public let packageWatts: Double

  /// Time when the sample was captured.
  public let timestamp: Date

  /// Creates a new power sample.
  ///
  /// - Parameters:
  ///   - cpuWatts: CPU power consumption in watts.
  ///   - gpuWatts: GPU power consumption in watts.
  ///   - aneWatts: ANE power consumption in watts.
  ///   - packageWatts: Total package power consumption in watts.
  ///   - timestamp: Time of capture. Defaults to `Date()`.
  public init(
    cpuWatts: Double,
    gpuWatts: Double,
    aneWatts: Double,
    packageWatts: Double,
    timestamp: Date = Date()
  ) {
    self.cpuWatts = cpuWatts
    self.gpuWatts = gpuWatts
    self.aneWatts = aneWatts
    self.packageWatts = packageWatts
    self.timestamp = timestamp
  }
}

/// Power domains that can be sampled by `powermetrics`.
///
/// Used with ``PowerMetricsCollector/start(domains:intervalMs:)`` to select
/// which hardware components to profile.
public struct PowerDomains: OptionSet, Sendable, Hashable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  /// Sample CPU power consumption.
  public static let cpu = PowerDomains(rawValue: 1 << 0)

  /// Sample GPU power consumption.
  public static let gpu = PowerDomains(rawValue: 1 << 1)

  /// Sample ANE (Neural Engine) power consumption.
  public static let ane = PowerDomains(rawValue: 1 << 2)

  /// Sample all available power domains (CPU, GPU, ANE).
  public static let all: PowerDomains = [.cpu, .gpu, .ane]
}
