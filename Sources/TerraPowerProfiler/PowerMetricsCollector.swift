#if os(macOS)
import Foundation

public enum PowerMetricsCollector {
  private static let lock = NSLock()
  private static var process: Process?
  private static var pipe: Pipe?

  private static let _isAvailable: Bool = FileManager.default.isExecutableFile(atPath: "/usr/bin/powermetrics")

  public static func isAvailable() -> Bool {
    _isAvailable
  }

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
