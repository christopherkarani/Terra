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

    var cpu = 0.0, gpu = 0.0, ane = 0.0, pkg = 0.0
    for s in samples {
      cpu += s.cpuWatts
      gpu += s.gpuWatts
      ane += s.aneWatts
      pkg += s.packageWatts
    }
    let count = Double(samples.count)
    return PowerSummary(
      averageCpuWatts: cpu / count,
      averageGpuWatts: gpu / count,
      averageAneWatts: ane / count,
      averagePackageWatts: pkg / count,
      sampleCount: samples.count
    )
  }
}
