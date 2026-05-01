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

  // MARK: - P1-12 Mid-Interval Spike Detection

  @Test("peak reflects mid-interval spike captured by observer")
  func thermalMonitor_peakReflectsMidIntervalSpike() {
    ThermalMonitor.reset()
    ThermalMonitor.install()
    defer { ThermalMonitor.reset() }

    let windowStart = Date(timeIntervalSince1970: 1000)
    let windowEnd = Date(timeIntervalSince1970: 1030)

    // Record a synthetic transition mid-window. We use the test hook because
    // ProcessInfo.thermalState cannot be mutated from tests without private API.
    ThermalMonitor.recordTransitionForTesting(
      state: .critical,
      timestamp: Date(timeIntervalSince1970: 1015)
    )

    let start = ThermalSample(state: .nominal, timestamp: windowStart)
    let end = ThermalSample(state: .nominal, timestamp: windowEnd)

    let profile = ThermalMonitor.profile(start: start, end: end)

    #expect(profile.peakState == .critical)
    #expect(profile.startState == .nominal)
    #expect(profile.endState == .nominal)
    // Throttled time covers the period from spike onset to the end of the window
    // (since recovery is unobserved). At minimum, throttled time must be positive.
    #expect(profile.timeInThrottledSeconds > 0)
  }

  @Test("transitions outside the window are ignored")
  func thermalMonitor_transitionsOutsideWindowIgnored() {
    ThermalMonitor.reset()
    ThermalMonitor.install()
    defer { ThermalMonitor.reset() }

    // Spike before window opens
    ThermalMonitor.recordTransitionForTesting(
      state: .critical,
      timestamp: Date(timeIntervalSince1970: 500)
    )
    // Spike after window closes
    ThermalMonitor.recordTransitionForTesting(
      state: .critical,
      timestamp: Date(timeIntervalSince1970: 2000)
    )

    let start = ThermalSample(state: .fair, timestamp: Date(timeIntervalSince1970: 1000))
    let end = ThermalSample(state: .nominal, timestamp: Date(timeIntervalSince1970: 1030))

    let profile = ThermalMonitor.profile(start: start, end: end)

    // Peak should be max(start, end) since out-of-window transitions are ignored
    #expect(profile.peakState == .fair)
  }

  @Test("multiple transitions inside the window pick the maximum")
  func thermalMonitor_multipleTransitionsPickMax() {
    ThermalMonitor.reset()
    ThermalMonitor.install()
    defer { ThermalMonitor.reset() }

    ThermalMonitor.recordTransitionForTesting(
      state: .fair,
      timestamp: Date(timeIntervalSince1970: 1005)
    )
    ThermalMonitor.recordTransitionForTesting(
      state: .serious,
      timestamp: Date(timeIntervalSince1970: 1015)
    )
    ThermalMonitor.recordTransitionForTesting(
      state: .nominal,
      timestamp: Date(timeIntervalSince1970: 1025)
    )

    let start = ThermalSample(state: .nominal, timestamp: Date(timeIntervalSince1970: 1000))
    let end = ThermalSample(state: .nominal, timestamp: Date(timeIntervalSince1970: 1030))

    let profile = ThermalMonitor.profile(start: start, end: end)

    #expect(profile.peakState == .serious)
  }

  @Test("reset clears observer and buffer")
  func thermalMonitor_resetClearsObserverAndBuffer() {
    ThermalMonitor.reset()
    ThermalMonitor.install()

    ThermalMonitor.recordTransitionForTesting(
      state: .critical,
      timestamp: Date(timeIntervalSince1970: 1015)
    )
    #expect(ThermalMonitor.bufferedTransitionCountForTesting() == 1)

    ThermalMonitor.reset()

    // Buffer must be empty after reset
    #expect(ThermalMonitor.bufferedTransitionCountForTesting() == 0)
    #expect(!ThermalMonitor.isInstalled)

    // After reset, recording should be a no-op (observer removed, buffer untouched)
    // Manually post the system notification — should NOT be captured.
    NotificationCenter.default.post(
      name: ProcessInfo.thermalStateDidChangeNotification,
      object: ProcessInfo.processInfo
    )
    #expect(ThermalMonitor.bufferedTransitionCountForTesting() == 0)
  }

  @Test("observer captures real notifications when installed")
  func thermalMonitor_observerCapturesRealNotifications() {
    ThermalMonitor.reset()
    ThermalMonitor.install()
    defer { ThermalMonitor.reset() }

    let before = ThermalMonitor.bufferedTransitionCountForTesting()

    NotificationCenter.default.post(
      name: ProcessInfo.thermalStateDidChangeNotification,
      object: ProcessInfo.processInfo
    )

    // The notification is dispatched on the main queue; give it a moment.
    let deadline = Date().addingTimeInterval(2.0)
    while Date() < deadline,
      ThermalMonitor.bufferedTransitionCountForTesting() <= before
    {
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }

    #expect(ThermalMonitor.bufferedTransitionCountForTesting() > before)
  }

  @Test("concurrent transitions are thread-safe")
  func thermalMonitor_concurrentTransitionsAreSafe() async {
    ThermalMonitor.reset()
    ThermalMonitor.install()
    defer { ThermalMonitor.reset() }

    let baseTime = Date(timeIntervalSince1970: 1000)
    let windowEnd = baseTime.addingTimeInterval(60)

    // Fire many transitions from concurrent tasks.
    await withTaskGroup(of: Void.self) { group in
      for i in 0..<200 {
        group.addTask {
          let state: ProcessInfo.ThermalState = (i % 4 == 3) ? .critical : .fair
          let ts = baseTime.addingTimeInterval(Double(i) * 0.01)
          ThermalMonitor.recordTransitionForTesting(state: state, timestamp: ts)
        }
      }
    }

    let start = ThermalSample(state: .nominal, timestamp: baseTime)
    let end = ThermalSample(state: .nominal, timestamp: windowEnd)

    // No crash, and peak is the highest observed state (.critical).
    let profile = ThermalMonitor.profile(start: start, end: end)
    #expect(profile.peakState == .critical)
  }

  @Test("buffer is bounded — oldest transitions evicted past capacity")
  func thermalMonitor_bufferBounded() {
    ThermalMonitor.reset()
    ThermalMonitor.install()
    defer { ThermalMonitor.reset() }

    let capacity = ThermalMonitor.transitionBufferCapacityForTesting

    // Push capacity + 50 transitions
    for i in 0..<(capacity + 50) {
      ThermalMonitor.recordTransitionForTesting(
        state: .fair,
        timestamp: Date(timeIntervalSince1970: Double(i))
      )
    }

    #expect(ThermalMonitor.bufferedTransitionCountForTesting() == capacity)
  }
}
