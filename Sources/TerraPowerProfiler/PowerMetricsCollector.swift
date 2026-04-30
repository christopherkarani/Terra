#if os(macOS)
import Foundation
import Darwin

/// Collector for hardware power metrics using `powermetrics`.
///
/// ``PowerMetricsCollector`` wraps the macOS `powermetrics` tool to capture CPU, GPU, and ANE
/// power consumption samples. This collector is only available on macOS and requires
/// elevated privileges.
///
/// - Important: `powermetrics` requires sudo access. Use ``startWithStatus(domains:intervalMs:)``
///   or ``lastStartResult`` to inspect launch failures on systems without sufficient privileges.
///
/// ## Usage
/// ```swift
/// // Start collecting power metrics
/// PowerMetricsCollector.start(domains: [.cpu, .gpu, .ane], intervalMs: 500)
///
/// // ... run your workload ...
///
/// // Stop and get the summary
/// let summary = PowerMetricsCollector.stop()
/// span.setAttributes(summary)
/// ```
///
/// - Note: On sandboxed macOS apps, `Process.run()` may throw a Cocoa
///   "operation not permitted" error. Such failures are classified as
///   ``StartResult/permissionDenied`` so callers can detect them without
///   string-parsing the failure description.
///
/// - SeeAlso: ``PowerSummary``, ``PowerSample``
public enum PowerMetricsCollector {
  private static let stopTimeoutSeconds: TimeInterval = 2
  private static let stopPollIntervalSeconds: TimeInterval = 0.01

  public enum StartResult: Equatable, Sendable {
    case started
    case alreadyRunning
    case unavailable
    case permissionDenied
    case failed(String)

    public var didStart: Bool {
      if case .started = self { return true }
      return false
    }
  }

  /// Minimal lifecycle surface PowerMetricsCollector needs from a child
  /// process. Production uses `Foundation.Process` via `_FoundationProcessHandle`;
  /// tests inject mocks to exercise the SIGKILL escalation path without
  /// spawning a real powermetrics child.
  package protocol ProcessHandle: AnyObject, Sendable {
    var isRunning: Bool { get }
    func terminate()
    func sendSIGKILL()
  }

  private static let lock = NSLock()
  private static var process: Process?
  private static var pipe: Pipe?
  private static var errorPipe: Pipe?
  private static var outputBuffer: PipeOutputBuffer?
  private static var errorBuffer: PipeOutputBuffer?
  private static var lastStartResultValue: StartResult?

  private static let _isAvailable: Bool = FileManager.default.isExecutableFile(atPath: "/usr/bin/powermetrics")

  /// Returns `true` if powermetrics is available on this system.
  ///
  /// Checks whether the `powermetrics` executable exists at `/usr/bin/powermetrics`.
  /// Returns `false` on non-macOS platforms or if the tool is not installed.
  public static func isAvailable() -> Bool {
    _isAvailable
  }

  public static var lastStartResult: StartResult? {
    lock.lock()
    defer { lock.unlock() }
    return lastStartResultValue
  }

  /// Starts collecting power metrics.
  ///
  /// Spawns a background `powermetrics` process that samples power consumption
  /// at the specified interval. Collection continues in the background until
  /// ``stop()`` is called.
  ///
  /// - Parameters:
  ///   - domains: Which power domains to sample (CPU, GPU, ANE). Defaults to `.all`.
  ///   - intervalMs: Sampling interval in milliseconds. Defaults to `1000`.
  ///
  /// - Note: Call ``stop()`` to end collection and retrieve the summary.
  ///   Nested calls while a session is active are ignored.
  public static func start(domains: PowerDomains = .all, intervalMs: Int = 1000) {
    _ = startWithStatus(domains: domains, intervalMs: intervalMs)
  }

  @discardableResult
  public static func startWithStatus(domains: PowerDomains = .all, intervalMs: Int = 1000) -> StartResult {
    _registerShutdownObserverIfNeeded()
    lock.lock()
    defer { lock.unlock() }

    guard _isAvailable else {
      lastStartResultValue = .unavailable
      return .unavailable
    }

    guard process == nil else {
      lastStartResultValue = .alreadyRunning
      return .alreadyRunning
    }

    var samplers: [String] = []
    if domains.contains(.cpu) { samplers.append("cpu_power") }
    if domains.contains(.gpu) { samplers.append("gpu_power") }
    if domains.contains(.ane) { samplers.append("ane_power") }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
    proc.arguments = [
      "--samplers", samplers.joined(separator: ","),
      "--sample-rate", "\(intervalMs)",
      "-n", "0",  // continuous
      "--format", "text",
    ]

    let outputPipe = Pipe()
    let stderrPipe = Pipe()
    let stdoutBuffer = PipeOutputBuffer()
    let stderrBuffer = PipeOutputBuffer()
    outputPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      guard !data.isEmpty else {
        handle.readabilityHandler = nil
        return
      }
      stdoutBuffer.append(data)
    }
    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      guard !data.isEmpty else {
        handle.readabilityHandler = nil
        return
      }
      stderrBuffer.append(data)
    }
    proc.standardOutput = outputPipe
    proc.standardError = stderrPipe

    do {
      try proc.run()
      process = proc
      pipe = outputPipe
      errorPipe = stderrPipe
      outputBuffer = stdoutBuffer
      errorBuffer = stderrBuffer
      lastStartResultValue = .started
      return .started
    } catch {
      outputPipe.fileHandleForReading.readabilityHandler = nil
      stderrPipe.fileHandleForReading.readabilityHandler = nil
      // P1-11: Sandboxed Cocoa "operation not permitted" surfaces are
      // permission-class failures. Distinguish them from generic spawn
      // failures so callers can branch without string-parsing.
      let nsError = error as NSError
      let result = _classifyStartError(
        domain: nsError.domain,
        code: nsError.code,
        fallback: error.localizedDescription
      )
      lastStartResultValue = result
      return result
    }
  }

  /// Stops power metrics collection and returns a summary.
  ///
  /// Terminates the background `powermetrics` process, parses all collected samples,
  /// and returns a ``PowerSummary`` with averaged power consumption across all domains.
  ///
  /// On the timeout path (the child fails to acknowledge `terminate()` within
  /// the deadline) the implementation:
  /// 1. Sends SIGKILL via `Darwin.kill(pid, SIGKILL)` so the orphan is reaped.
  /// 2. Returns whatever bytes the readability handler already buffered, instead
  ///    of calling `readDataToEndOfFile()` (which would block while the child
  ///    still owns the write end of the pipe).
  ///
  /// - Returns: ``PowerSummary`` containing average power consumption.
  ///   If collection was not active, returns a zero-filled summary.
  public static func stop() -> PowerSummary {
    lock.lock()
    let proc = process
    let outputPipe = pipe
    let stderrPipe = errorPipe
    let stdoutBuffer = outputBuffer
    let stderrBuffer = errorBuffer
    process = nil
    pipe = nil
    errorPipe = nil
    outputBuffer = nil
    errorBuffer = nil
    lock.unlock()

    guard let proc, let outputPipe, let stderrPipe, let stdoutBuffer, let stderrBuffer else {
      return PowerSummary.from([], status: .notStarted)
    }

    let handle = _FoundationProcessHandle(process: proc)
    let result = _stopProcessForTesting(
      handle,
      timeoutSeconds: stopTimeoutSeconds,
      pollIntervalSeconds: stopPollIntervalSeconds
    )

    outputPipe.fileHandleForReading.readabilityHandler = nil
    stderrPipe.fileHandleForReading.readabilityHandler = nil

    // P1-11: do NOT call readDataToEndOfFile() on the timeout path — the
    // child may still hold the write end of the pipe and EOF would never
    // arrive, blocking the calling thread. Use whatever the readability
    // handler already buffered.
    if result.terminated {
      stdoutBuffer.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
      stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
    }
    let output = stdoutBuffer.string()
    let stderr = stderrBuffer.string()

    let terminationStatus: Int32
    if result.terminated && !result.killed {
      terminationStatus = proc.terminationStatus
    } else {
      // Either we escalated to SIGKILL or the child is still running. Report
      // as a generic failure so the summaryForTesting classifier flags it.
      terminationStatus = -1
    }

    return summaryForTesting(
      stdout: output,
      stderr: stderr,
      terminationStatus: terminationStatus
    )
  }

  /// Stops collection if currently active, otherwise no-op.
  ///
  /// Designed for shutdown paths that need to ensure the powermetrics child
  /// is reaped without caring whether a caller previously started a session.
  /// Safe to call repeatedly. Must not block beyond the configured stop
  /// timeout (currently 2s + 2s SIGKILL grace).
  public static func stopIfActive() {
    lock.lock()
    let isActive = process != nil
    lock.unlock()

    guard isActive else { return }
    _ = stop()
  }

  package static func summaryForTesting(
    stdout: String,
    stderr: String,
    terminationStatus: Int32
  ) -> PowerSummary {
    // powermetrics outputs multiple samples separated by "***"
    var samples: [PowerSample] = []
    let sections = stdout.components(separatedBy: "***")
    for section in sections {
      if let sample = PowerMetricsParser.parse(section) {
        samples.append(sample)
      }
    }

    guard samples.isEmpty else {
      return PowerSummary.from(samples, status: .completed)
    }

    let diagnostic = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    if looksLikePermissionFailure(diagnostic) {
      return PowerSummary.from(
        [],
        status: .permissionDenied,
        diagnosticMessage: diagnostic.isEmpty ? nil : diagnostic
      )
    }

    if terminationStatus != 0 {
      return PowerSummary.from(
        [],
        status: .failed,
        diagnosticMessage: diagnostic.isEmpty ? "powermetrics exited with status \(terminationStatus)" : diagnostic
      )
    }

    return PowerSummary.from(
      [],
      status: .noSamples,
      diagnosticMessage: diagnostic.isEmpty ? nil : diagnostic
    )
  }

  private static func looksLikePermissionFailure(_ stderr: String) -> Bool {
    let lowercased = stderr.lowercased()
    return lowercased.contains("permission")
      || lowercased.contains("operation not permitted")
      || lowercased.contains("must be run as root")
      || lowercased.contains("sudo")
  }

  /// Result of a stop attempt against a ``ProcessHandle``.
  package struct StopResult: Sendable, Equatable {
    package let terminated: Bool
    package let killed: Bool
  }

  /// Internal seam used by both production `stop()` and tests.
  ///
  /// 1. Calls `terminate()` on the handle.
  /// 2. Polls until the deadline; if the handle is still running after the
  ///    deadline, escalates to SIGKILL via `sendSIGKILL()` and polls again
  ///    for a brief grace period.
  /// 3. Returns whether the handle is now stopped, and whether the SIGKILL
  ///    escalation fired.
  ///
  /// This function never calls `Foundation.FileHandle.readDataToEndOfFile()`,
  /// so it cannot block on a child that is still holding the write end of a
  /// pipe.
  @discardableResult
  package static func _stopProcessForTesting(
    _ handle: ProcessHandle,
    timeoutSeconds: TimeInterval,
    pollIntervalSeconds: TimeInterval
  ) -> StopResult {
    if handle.isRunning {
      handle.terminate()
    }

    var deadline = Date().addingTimeInterval(timeoutSeconds)
    while handle.isRunning && Date() < deadline {
      Thread.sleep(forTimeInterval: pollIntervalSeconds)
    }

    if !handle.isRunning {
      return StopResult(terminated: true, killed: false)
    }

    // Escalate to SIGKILL — the child failed to acknowledge SIGTERM in time.
    handle.sendSIGKILL()

    deadline = Date().addingTimeInterval(timeoutSeconds)
    while handle.isRunning && Date() < deadline {
      Thread.sleep(forTimeInterval: pollIntervalSeconds)
    }

    return StopResult(terminated: !handle.isRunning, killed: true)
  }

  /// Classifies a `Process.run()` failure into a ``StartResult``.
  ///
  /// Sandboxed macOS apps surface "operation not permitted" as
  /// `NSCocoaErrorDomain` 257 (`NSFileReadNoPermissionError`) or as
  /// `NSPOSIXErrorDomain` `EACCES`/`EPERM`. Both must classify as
  /// ``StartResult/permissionDenied`` rather than ``StartResult/failed``.
  package static func _classifyStartErrorForTesting(
    domain: String,
    code: Int
  ) -> StartResult {
    _classifyStartError(domain: domain, code: code, fallback: nil)
  }

  private static func _classifyStartError(
    domain: String,
    code: Int,
    fallback: String?
  ) -> StartResult {
    if domain == NSCocoaErrorDomain {
      // 257: NSFileReadNoPermissionError, 513: NSFileWriteNoPermissionError
      if code == 257 || code == 513 {
        return .permissionDenied
      }
    }
    if domain == NSPOSIXErrorDomain {
      // EACCES (13) and EPERM (1) both indicate a permission boundary.
      if code == 1 || code == 13 {
        return .permissionDenied
      }
    }
    return .failed(fallback ?? "Process launch failed (\(domain) \(code))")
  }

  // P1-10: Register a one-shot Notification observer that drains the
  // powermetrics child when the umbrella posts the shutdown notification.
  // Registered lazily (on first start) because the umbrella does not depend
  // on TerraPowerProfiler — there is no eager bootstrap point.
  private static let shutdownObserverLock = NSLock()
  private nonisolated(unsafe) static var shutdownObserverRegistered = false

  private static func _registerShutdownObserverIfNeeded() {
    shutdownObserverLock.lock()
    defer { shutdownObserverLock.unlock() }
    guard !shutdownObserverRegistered else { return }
    shutdownObserverRegistered = true

    NotificationCenter.default.addObserver(
      forName: Notification.Name("TerraDidRequestProfilerShutdown"),
      object: nil,
      queue: nil
    ) { _ in
      PowerMetricsCollector.stopIfActive()
    }
  }
}

/// Production wrapper around `Foundation.Process` so the SIGKILL-escalation
/// helper can drive both real children and test mocks through a uniform
/// surface.
private final class _FoundationProcessHandle: PowerMetricsCollector.ProcessHandle, @unchecked Sendable {
  private let process: Process

  init(process: Process) {
    self.process = process
  }

  var isRunning: Bool {
    process.isRunning
  }

  func terminate() {
    if process.isRunning {
      process.terminate()
    }
  }

  func sendSIGKILL() {
    let pid = process.processIdentifier
    guard pid > 0 else { return }
    _ = Darwin.kill(pid, SIGKILL)
  }
}

private final class PipeOutputBuffer: @unchecked Sendable {
  private let lock = NSLock()
  private var data = Data()

  func append(_ chunk: Data) {
    guard !chunk.isEmpty else { return }
    lock.lock()
    data.append(chunk)
    lock.unlock()
  }

  func string() -> String {
    lock.lock()
    let snapshot = data
    lock.unlock()
    return String(data: snapshot, encoding: .utf8) ?? ""
  }
}
#endif
