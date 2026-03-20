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
  }
}
#endif
