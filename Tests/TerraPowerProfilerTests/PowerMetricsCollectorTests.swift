#if os(macOS)
import Foundation
import Testing
@testable import TerraPowerProfiler

@Suite("PowerMetricsCollector")
struct PowerMetricsCollectorTests {

  @Test("isAvailable probes for powermetrics binary")
  func isAvailableProbe() {
    // On macOS, powermetrics should exist
    let available = PowerMetricsCollector.isAvailable()
    #expect(available == true)
  }

  @Test("stop without start returns empty summary")
  func stopWithoutStart() {
    let summary = PowerMetricsCollector.stop()
    #expect(summary.sampleCount == 0)
    #expect(summary.status == .notStarted)
  }

  @Test("permission stderr is visible in stop summary")
  func permissionFailureSummary() {
    let summary = PowerMetricsCollector.summaryForTesting(
      stdout: "",
      stderr: "powermetrics must be run as root",
      terminationStatus: 1
    )

    #expect(summary.sampleCount == 0)
    #expect(summary.status == .permissionDenied)
    #expect(summary.diagnosticMessage?.contains("root") == true)
  }

  @Test("empty successful output reports no samples")
  func noSamplesSummary() {
    let summary = PowerMetricsCollector.summaryForTesting(
      stdout: "",
      stderr: "",
      terminationStatus: 0
    )

    #expect(summary.sampleCount == 0)
    #expect(summary.status == .noSamples)
  }
}
#endif
