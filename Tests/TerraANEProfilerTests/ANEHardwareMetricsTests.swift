import Foundation
import Testing
import OpenTelemetryApi
import CTerraANEBridge
@testable import TerraANEProfiler

@Suite("ANEHardwareMetrics", .serialized)
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
    #expect(attrs["terra.hw.ane.hw_execution_time_ns"] == AttributeValue.int(10000))
    #expect(attrs["terra.hw.ane.host_overhead_ms"] == AttributeValue.double(0.0025))
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

@Suite("ANEHardwareProfiler", .serialized)
struct ANEHardwareProfilerTests {

  @Test("availability probe runs without crash")
  func availabilityProbe() {
    // Just verify the API is callable — actual availability depends on device
    _ = ANEHardwareProfiler.isAvailable
  }

  @Test("probe availability does not imply active metric collection")
  func availabilityDoesNotImplyCollection() {
    ANEHardwareProfiler.reset()
    let installed = ANEHardwareProfiler.install()

    if !installed {
      #expect(ANEHardwareProfiler.isCollecting == false)
    }
  }

  @Test("mode makes probe-only status explicit")
  func modeClassifiesProbeOnlySeparatelyFromCollection() {
    let mode = ANEHardwareProfiler.mode
    #expect([.unavailable, .probeOnly, .collecting].contains(mode))
    if mode == .probeOnly {
      #expect(ANEHardwareProfiler.isAvailable == true)
      #expect(ANEHardwareProfiler.isCollecting == false)
    }
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

  // P0-7: App Store private-API gating must be safe-by-default.
  //
  // Without explicit opt-in (`ENABLE_ANE_PRIVATE_APIS`), the bridge MUST NOT
  // reach the private `_ANEPerformanceStats` symbol. That keeps app archives
  // safe regardless of build configuration: TestFlight builds spawned in
  // DEBUG cannot accidentally ship the private string.
  @Test("ANE bridge is App Store safe by default")
  func testANEBridgeIsAppStoreSafeByDefault() {
    #if ENABLE_ANE_PRIVATE_APIS
    // Opt-in build: skip — covered by other tests.
    #else
    #expect(terra_ane_is_available() == false)
    #expect(terra_ane_is_collecting() == false)
    #expect(terra_ane_install_swizzling() == false)
    #endif
  }

  // P0-7: install() must report failure on App Store builds.
  @Test("ANEHardwareProfiler.install returns false in App Store default")
  func testANEHardwareProfilerInstallReturnsFalseInAppStoreDefault() {
    #if ENABLE_ANE_PRIVATE_APIS
    // Opt-in build: install may succeed depending on device/OS — skip.
    #else
    ANEHardwareProfiler.reset()
    let result = ANEHardwareProfiler.install()
    #expect(result == false)
    #expect(ANEHardwareProfiler.isInstalled == false)
    #expect(ANEHardwareProfiler.mode == .unavailable)
    #endif
  }

  // P1-10: reset() must clear isInstalled so shutdown can re-prove start state.
  @Test("ANEHardwareProfiler reset clears install state")
  func testANEHardwareProfilerResetClearsInstallState() {
    ANEHardwareProfiler.reset()
    #expect(ANEHardwareProfiler.isInstalled == false)

    // Even if install succeeded, reset must restore false.
    _ = ANEHardwareProfiler.install()
    ANEHardwareProfiler.reset()
    #expect(ANEHardwareProfiler.isInstalled == false)
  }
}

@Suite("ANEProfilerSession", .serialized)
struct ANEProfilerSessionTests {

  @Test("stop without start returns metrics")
  func stopWithoutStart() {
    let metrics = ANEProfilerSession.stop()
    _ = metrics.telemetryAttributes
  }

  @Test("start/stop lifecycle")
  func startStopLifecycle() {
    let result = ANEProfilerSession.startWithStatus()
    if ANEHardwareProfiler.mode == .collecting {
      #expect(result == .startedCollecting || result == .alreadyActive)
      #expect(ANEProfilerSession.isActive == true)
    } else {
      #expect(result == .probeOnly || result == .unavailable)
      #expect(ANEProfilerSession.isActive == false)
    }
    let metrics = ANEProfilerSession.stop()
    _ = metrics.telemetryAttributes
  }

  // P1-10: stopIfActive() must be a safe no-op when no session is active.
  @Test("stopIfActive is safe when no session is active")
  func stopIfActiveNoOp() {
    // Ensure clean state.
    _ = ANEProfilerSession.stop()
    #expect(ANEProfilerSession.isActive == false)

    // No-op call should not crash and should leave state unchanged.
    ANEProfilerSession.stopIfActive()
    #expect(ANEProfilerSession.isActive == false)
  }

  // P1-10: stopIfActive() must gracefully stop a live session.
  @Test("stopIfActive gracefully stops a live session")
  func stopIfActiveStopsLiveSession() {
    _ = ANEProfilerSession.stop()

    let result = ANEProfilerSession.startWithStatus()
    if result == .startedCollecting {
      #expect(ANEProfilerSession.isActive == true)
      ANEProfilerSession.stopIfActive()
      #expect(ANEProfilerSession.isActive == false)
    } else {
      // Cannot start collection on this machine — stopIfActive is still safe.
      ANEProfilerSession.stopIfActive()
      #expect(ANEProfilerSession.isActive == false)
    }
  }
}
