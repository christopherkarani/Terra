#if os(macOS)
import Foundation
import OpenTelemetryApi
import TerraSystemProfiler

public enum EspressoLogCapture {
  private static let lock = NSLock()
  private static var process: Process?
  private static var pipe: Pipe?

  public static func start() {
    lock.lock()
    defer { lock.unlock() }

    guard process == nil else { return }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    proc.arguments = [
      "stream",
      "--predicate", "subsystem == 'com.apple.espresso'",
      "--info",
      "--debug",
      "--style", "compact",
    ]

    let outputPipe = Pipe()
    proc.standardOutput = outputPipe
    proc.standardError = FileHandle.nullDevice

    do {
      try proc.run()
      process = proc
      pipe = outputPipe
    } catch {
      // Failed to start — ignore, capture will return empty summary
    }
  }

  public static func stop() -> EspressoLogSummary {
    lock.lock()
    let proc = process
    let outputPipe = pipe
    process = nil
    pipe = nil
    lock.unlock()

    guard let proc, let outputPipe else {
      return EspressoLogParser.summarize([])
    }

    proc.terminate()
    proc.waitUntilExit()

    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    let entries = EspressoLogParser.parse(output)
    return EspressoLogParser.summarize(entries)
  }
}
#endif
