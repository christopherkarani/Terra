import Foundation
import OpenTelemetryApi
import TerraSystemProfiler

public struct PowerSample: Sendable, Codable, Hashable {
  public let cpuWatts: Double
  public let gpuWatts: Double
  public let aneWatts: Double
  public let packageWatts: Double
  public let timestamp: Date

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

public struct PowerDomains: OptionSet, Sendable, Hashable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  public static let cpu = PowerDomains(rawValue: 1 << 0)
  public static let gpu = PowerDomains(rawValue: 1 << 1)
  public static let ane = PowerDomains(rawValue: 1 << 2)
  public static let all: PowerDomains = [.cpu, .gpu, .ane]
}
