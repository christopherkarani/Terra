import Foundation
import Testing
import OpenTelemetryApi
@testable import TerraPowerProfiler

@Suite("PowerSummary")
struct PowerSummaryTests {

  @Test("averages multiple samples")
  func averaging() {
    let samples = [
      PowerSample(cpuWatts: 2.0, gpuWatts: 1.0, aneWatts: 0.5, packageWatts: 3.5),
      PowerSample(cpuWatts: 4.0, gpuWatts: 3.0, aneWatts: 1.5, packageWatts: 8.5),
    ]

    let summary = PowerSummary.from(samples)
    #expect(summary.averageCpuWatts == 3.0)
    #expect(summary.averageGpuWatts == 2.0)
    #expect(summary.averageAneWatts == 1.0)
    #expect(summary.averagePackageWatts == 6.0)
    #expect(summary.sampleCount == 2)
  }

  @Test("empty samples produce zero summary")
  func emptySamples() {
    let summary = PowerSummary.from([])
    #expect(summary.averageCpuWatts == 0)
    #expect(summary.sampleCount == 0)
  }

  @Test("telemetry attributes output")
  func telemetryAttributes() {
    let samples = [
      PowerSample(cpuWatts: 2.0, gpuWatts: 1.0, aneWatts: 0.5, packageWatts: 3.5),
    ]
    let summary = PowerSummary.from(samples)
    let attrs = summary.telemetryAttributes

    #expect(attrs["terra.power.cpu_watts"] == AttributeValue.double(2.0))
    #expect(attrs["terra.power.gpu_watts"] == AttributeValue.double(1.0))
    #expect(attrs["terra.power.ane_watts"] == AttributeValue.double(0.5))
    #expect(attrs["terra.power.package_watts"] == AttributeValue.double(3.5))
    #expect(attrs["terra.power.sample_count"] == AttributeValue.int(1))
  }
}
