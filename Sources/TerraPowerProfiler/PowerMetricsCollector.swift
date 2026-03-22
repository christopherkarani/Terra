#if os(macOS)
import Foundation

/// Collector for hardware power metrics using `powermetrics`.
///
/// ``PowerMetricsCollector`` wraps the macOS `powermetrics` tool to capture CPU, GPU, and ANE
/// power consumption samples. This collector is only available on macOS and requires
/// elevated privileges.
///
/// - Important: `powermetrics` requires sudo access. The collector will fail silently
///   if run without sufficient privileges.
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
  private static let lock = NSLock()
  private static var process: Process?
  private static var pipe: Pipe?

  private static let _isAvailable: Bool = FileManager.default.isExecutableFile(atPath: "/usr/bin/powermetrics")

  /// Returns `true` if powermetrics is available on this system.
  ///
  /// Checks whether the `powermetrics` executable exists at `/usr/bin/powermetrics`.
  /// Returns `false` on non-macOS platforms or if the tool is not installed.
  public static func isAvailable() -> Bool {
    _isAvailable
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
    lock.lock()
    defer { lock.unlock() }

    guard process == nil else { return }

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
    proc.standardOutput = outputPipe
    proc.standardError = FileHandle.nullDevice

    do {
      try proc.run()
      process = proc
      pipe = outputPipe
    } catch {
      // powermetrics requires sudo — will fail without it
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
    process = nil
    pipe = nil
    lock.unlock()

    guard let proc, let outputPipe else {
      return PowerSummary.from([])
    }

    proc.terminate()
    proc.waitUntilExit()

    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    // powermetrics outputs multiple samples separated by "***"
    var samples: [PowerSample] = []
    let sections = output.components(separatedBy: "***")
    for section in sections {
      if let sample = PowerMetricsParser.parse(section) {
        samples.append(sample)
      }
    }

    return PowerSummary.from(samples)
  }
}
#endif
