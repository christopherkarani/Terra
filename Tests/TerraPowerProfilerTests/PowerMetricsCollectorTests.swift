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

  @Test("unbounded stop timeout reports failed collection")
  func boundedStopTimeoutSummary() {
    let summary = PowerMetricsCollector.summaryForTesting(
      stdout: "",
      stderr: "",
      terminationStatus: -1
    )

    #expect(summary.sampleCount == 0)
    #expect(summary.status == .failed)
    #expect(summary.diagnosticMessage?.contains("-1") == true)
  }

  // P1-10: stopIfActive should be a no-op when no collection is in flight.
  @Test("stopIfActive is a safe no-op when not running")
  func stopIfActiveNoOp() {
    // Drain any prior state.
    _ = PowerMetricsCollector.stop()
    PowerMetricsCollector.stopIfActive()
    let summary = PowerMetricsCollector.stop()
    #expect(summary.sampleCount == 0)
    #expect(summary.status == .notStarted)
  }

  // P1-11: stop() must NOT block when the timeout fires; it must return
  // within a deterministic budget. We exercise the seam directly.
  @Test("stop does not block on timeout path")
  func testPowerMetricsCollectorStopDoesNotBlockOnTimeout() {
    let mock = MockProcessHandle(remainsRunning: true)
    let start = Date()
    let result = PowerMetricsCollector._stopProcessForTesting(
      mock,
      timeoutSeconds: 0.2,
      pollIntervalSeconds: 0.01
    )
    let elapsed = Date().timeIntervalSince(start)
    #expect(elapsed < 3.0, "stop should not block — elapsed=\(elapsed)")
    #expect(result.terminated == false || result.killed == true,
            "the test mock never terminates without SIGKILL")
    #expect(result.killed == true,
            "stop must escalate to SIGKILL once terminate timed out")
  }

  // P1-11: After terminate() deadline expires, the implementation MUST
  // escalate to SIGKILL via Darwin.kill so the orphan child is reaped.
  @Test("stop escalates to SIGKILL after terminate deadline")
  func testPowerMetricsCollectorStopEscalatesToSIGKILL() {
    let mock = MockProcessHandle(remainsRunning: true)
    let result = PowerMetricsCollector._stopProcessForTesting(
      mock,
      timeoutSeconds: 0.2,
      pollIntervalSeconds: 0.01
    )
    #expect(mock.terminateCalled == true)
    #expect(mock.sigkillCalled == true)
    #expect(result.killed == true)
  }

  // P1-11: A process that exits cooperatively before the deadline must NOT
  // trigger the SIGKILL escalation.
  @Test("stop does not escalate when process exits before deadline")
  func stopHonorsCooperativeShutdown() {
    let mock = MockProcessHandle(remainsRunning: false)
    let result = PowerMetricsCollector._stopProcessForTesting(
      mock,
      timeoutSeconds: 0.2,
      pollIntervalSeconds: 0.01
    )
    #expect(result.terminated == true)
    #expect(result.killed == false)
    #expect(mock.sigkillCalled == false)
  }

  // P1-11: Cocoa "operation not permitted" surfaces from sandboxed callers
  // must be classified as `.permissionDenied`, not `.failed`.
  @Test("start failure from Cocoa unauthorized classifies as permissionDenied")
  func testStartFailureFromCocoaUnauthorizedClassifiesAsPermissionDenied() {
    let cocoa = PowerMetricsCollector._classifyStartErrorForTesting(
      domain: NSCocoaErrorDomain,
      code: 257  // NSFileReadNoPermissionError
    )
    #expect(cocoa == .permissionDenied)

    let posix = PowerMetricsCollector._classifyStartErrorForTesting(
      domain: NSPOSIXErrorDomain,
      code: 13  // EACCES
    )
    #expect(posix == .permissionDenied)

    // Unrelated errors must still classify as .failed.
    let other = PowerMetricsCollector._classifyStartErrorForTesting(
      domain: NSCocoaErrorDomain,
      code: 4  // NSFileNoSuchFileError
    )
    if case .failed = other {
      // expected
    } else {
      Issue.record("expected .failed for unrelated error, got \(other)")
    }
  }
}

/// Test double that mimics the subset of `Foundation.Process` lifecycle
/// PowerMetricsCollector needs to terminate or escalate to SIGKILL.
final class MockProcessHandle: PowerMetricsCollector.ProcessHandle, @unchecked Sendable {
  private let lock = NSLock()
  private var _isRunning: Bool
  private let exitOnTerminate: Bool
  private(set) var terminateCalled: Bool = false
  private(set) var sigkillCalled: Bool = false

  init(remainsRunning: Bool) {
    self._isRunning = true
    self.exitOnTerminate = !remainsRunning
  }

  var isRunning: Bool {
    lock.lock()
    defer { lock.unlock() }
    return _isRunning
  }

  func terminate() {
    lock.lock()
    terminateCalled = true
    if exitOnTerminate {
      _isRunning = false
    }
    lock.unlock()
  }

  func sendSIGKILL() {
    lock.lock()
    sigkillCalled = true
    _isRunning = false
    lock.unlock()
  }
}
#endif
