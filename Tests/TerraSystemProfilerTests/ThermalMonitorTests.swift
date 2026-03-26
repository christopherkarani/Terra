import Foundation
import Testing
import OpenTelemetryApi
@testable import TerraSystemProfiler

@Suite("ThermalMonitor", .serialized)
struct ThermalMonitorTests {

  @Test("state labels for all thermal states")
  func stateLabels() {
    #expect(ThermalMonitor.stateLabel(.nominal) == "nominal")
    #expect(ThermalMonitor.stateLabel(.fair) == "fair")
    #expect(ThermalMonitor.stateLabel(.serious) == "serious")
    #expect(ThermalMonitor.stateLabel(.critical) == "critical")
  }

  @Test("sample returns current state")
  func sampleReturnsState() {
    let sample = ThermalMonitor.sample()
    // We can't predict the state, but it should be a valid value
    let label = ThermalMonitor.stateLabel(sample.state)
    #expect(["nominal", "fair", "serious", "critical"].contains(label))
  }

  @Test("profile computes peak state correctly")
  func profilePeakState() {
    let start = ThermalSample(state: .nominal, timestamp: Date(timeIntervalSince1970: 100))
    let end = ThermalSample(state: .serious, timestamp: Date(timeIntervalSince1970: 110))

    let profile = ThermalMonitor.profile(start: start, end: end)

    #expect(profile.peakState == .serious)
    #expect(profile.startState == .nominal)
    #expect(profile.endState == .serious)
  }

  @Test("profile computes duration correctly")
  func profileDuration() {
    let start = ThermalSample(state: .nominal, timestamp: Date(timeIntervalSince1970: 100))
    let end = ThermalSample(state: .nominal, timestamp: Date(timeIntervalSince1970: 105))

    let profile = ThermalMonitor.profile(start: start, end: end)

    #expect(profile.durationSeconds == 5.0)
  }

  @Test("profile computes throttled time when serious or critical")
  func profileThrottledTime() {
    let start = ThermalSample(state: .serious, timestamp: Date(timeIntervalSince1970: 100))
    let end = ThermalSample(state: .critical, timestamp: Date(timeIntervalSince1970: 108))

    let profile = ThermalMonitor.profile(start: start, end: end)

    #expect(profile.timeInThrottledSeconds == 8.0)
  }

  @Test("profile zero throttled time when below serious")
  func profileNoThrottledTime() {
    let start = ThermalSample(state: .nominal, timestamp: Date(timeIntervalSince1970: 100))
    let end = ThermalSample(state: .fair, timestamp: Date(timeIntervalSince1970: 105))

    let profile = ThermalMonitor.profile(start: start, end: end)

    #expect(profile.timeInThrottledSeconds == 0)
  }

  @Test("ThermalProfile telemetry attributes")
  func thermalProfileAttributes() {
    let start = ThermalSample(state: .nominal, timestamp: Date(timeIntervalSince1970: 100))
    let end = ThermalSample(state: .serious, timestamp: Date(timeIntervalSince1970: 110))
    let profile = ThermalMonitor.profile(start: start, end: end)

    let attrs = profile.telemetryAttributes
    #expect(attrs["terra.thermal.state"] == AttributeValue.string("serious"))
    #expect(attrs["terra.thermal.peak_state"] == AttributeValue.string("serious"))
    #expect(attrs["terra.thermal.time_throttled_s"] == AttributeValue.double(10.0))
  }

  @Test("install state management")
  func installStateManagement() {
    // ThermalMonitor uses shared static state; just verify the API shape
    _ = ThermalMonitor.isInstalled
    ThermalMonitor.install()
    #expect(ThermalMonitor.isInstalled)
  }
}
