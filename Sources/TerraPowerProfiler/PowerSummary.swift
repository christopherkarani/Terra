import Foundation
import OpenTelemetryApi
import TerraSystemProfiler

public struct PowerSummary: Sendable, TelemetryAttributeConvertible {
  public let averageCpuWatts: Double
  public let averageGpuWatts: Double
  public let averageAneWatts: Double
  public let averagePackageWatts: Double
  public let sampleCount: Int

  public var telemetryAttributes: [String: AttributeValue] {
    [
      "terra.power.cpu_watts": .double(averageCpuWatts),
      "terra.power.gpu_watts": .double(averageGpuWatts),
      "terra.power.ane_watts": .double(averageAneWatts),
      "terra.power.package_watts": .double(averagePackageWatts),
      "terra.power.sample_count": .int(sampleCount),
    ]
  }

  public static func from(_ samples: [PowerSample]) -> PowerSummary {
    guard !samples.isEmpty else {
      return PowerSummary(
        averageCpuWatts: 0,
        averageGpuWatts: 0,
        averageAneWatts: 0,
        averagePackageWatts: 0,
        sampleCount: 0
      )
    }

    let count = Double(samples.count)
    return PowerSummary(
      averageCpuWatts: samples.reduce(0) { $0 + $1.cpuWatts } / count,
      averageGpuWatts: samples.reduce(0) { $0 + $1.gpuWatts } / count,
      averageAneWatts: samples.reduce(0) { $0 + $1.aneWatts } / count,
      averagePackageWatts: samples.reduce(0) { $0 + $1.packageWatts } / count,
      sampleCount: samples.count
    )
  }
}
