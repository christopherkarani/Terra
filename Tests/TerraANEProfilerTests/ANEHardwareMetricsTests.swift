import Foundation
import Testing
import OpenTelemetryApi
import CTerraANEBridge
@testable import TerraANEProfiler

@Suite("ANEHardwareMetrics")
struct ANEHardwareMetricsTests {

  @Test("converts from C struct")
  func fromCStruct() {
    var cMetrics = terra_ane_metrics_t()
    cMetrics.hardware_execution_time_ns = 5000
    cMetrics.host_overhead_us = 1.5
    cMetrics.segment_count = 3
    cMetrics.fully_ane = true
    cMetrics.available = true

    let metrics = ANEHardwareMetrics(from: cMetrics)
    #expect(metrics.hardwareExecutionTimeNs == 5000)
    #expect(metrics.hostOverheadUs == 1.5)
    #expect(metrics.segmentCount == 3)
    #expect(metrics.fullyANE == true)
    #expect(metrics.available == true)
  }

  @Test("telemetry attributes output")
  func telemetryAttributes() {
    let metrics = ANEHardwareMetrics(
      hardwareExecutionTimeNs: 10000,
      hostOverheadUs: 2.5,
      segmentCount: 5,
      fullyANE: false,
      available: true
    )
    let attrs = metrics.telemetryAttributes

    #expect(attrs["terra.ane.hardware_execution_time_ns"] == AttributeValue.int(10000))
    #expect(attrs["terra.ane.host_overhead_us"] == AttributeValue.double(2.5))
    #expect(attrs["terra.ane.segment_count"] == AttributeValue.int(5))
    #expect(attrs["terra.ane.fully_ane"] == AttributeValue.bool(false))
    #expect(attrs["terra.ane.available"] == AttributeValue.bool(true))
  }

  @Test("zeroed C struct produces zeroed metrics")
  func zeroedStruct() {
    let cMetrics = terra_ane_metrics_t()
    let metrics = ANEHardwareMetrics(from: cMetrics)
    #expect(metrics.hardwareExecutionTimeNs == 0)
    #expect(metrics.available == false)
  }
}

@Suite("ANEHardwareProfiler")
struct ANEHardwareProfilerTests {

  @Test("availability probe runs without crash")
  func availabilityProbe() {
    // Just verify the API is callable — actual availability depends on device
    _ = ANEHardwareProfiler.isAvailable
  }

  @Test("captureMetrics returns valid struct")
  func captureMetrics() {
    let metrics = ANEHardwareProfiler.captureMetrics()
    // On test machines, ANE may not be available
    _ = metrics.telemetryAttributes
  }

  @Test("reset does not crash")
  func resetSafe() {
    ANEHardwareProfiler.reset()
  }
}

@Suite("ANEProfilerSession")
struct ANEProfilerSessionTests {

  @Test("stop without start returns metrics")
  func stopWithoutStart() {
    let metrics = ANEProfilerSession.stop()
    _ = metrics.telemetryAttributes
  }

  @Test("start/stop lifecycle")
  func startStopLifecycle() {
    ANEProfilerSession.start()
    let metrics = ANEProfilerSession.stop()
    _ = metrics.telemetryAttributes
  }
}
