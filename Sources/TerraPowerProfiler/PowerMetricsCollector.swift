#if os(macOS)
import Foundation

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
/// - SeeAlso: ``PowerSummary``, ``PowerSample``
public enum PowerMetricsCollector {
  public enum StartResult: Equatable, Sendable {
    case started
    case alreadyRunning
    case unavailable
    case failed(String)

    public var didStart: Bool {
      if case .started = self { return true }
      return false
    }
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
      let result = StartResult.failed(error.localizedDescription)
      lastStartResultValue = result
      return result
    }
  }

  /// Stops power metrics collection and returns a summary.
  ///
  /// Terminates the background `powermetrics` process, parses all collected samples,
  /// and returns a ``PowerSummary`` with averaged power consumption across all domains.
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

    proc.terminate()
    proc.waitUntilExit()

    outputPipe.fileHandleForReading.readabilityHandler = nil
    stderrPipe.fileHandleForReading.readabilityHandler = nil
    stdoutBuffer.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
    stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
    let output = stdoutBuffer.string()
    let stderr = stderrBuffer.string()

    return summaryForTesting(
      stdout: output,
      stderr: stderr,
      terminationStatus: proc.terminationStatus
    )
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
