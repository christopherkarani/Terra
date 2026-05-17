#if os(macOS)
import Darwin
import Foundation
import OpenTelemetryApi
import TerraSystemProfiler

public enum EspressoLogCapture {
  private static let lock = NSLock()
  private static var process: Process?
  private static var pipe: Pipe?
  private static var outputBuffer: EspressoPipeOutputBuffer?

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
    let buffer = EspressoPipeOutputBuffer()
    outputPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      guard !data.isEmpty else {
        handle.readabilityHandler = nil
        return
      }
      buffer.append(data)
    }
    proc.standardOutput = outputPipe
    proc.standardError = FileHandle.nullDevice

    do {
      try proc.run()
      process = proc
      pipe = outputPipe
      outputBuffer = buffer
    } catch {
      outputPipe.fileHandleForReading.readabilityHandler = nil
      // Failed to start — ignore, capture will return empty summary
    }
  }

  public static func stop() -> EspressoLogSummary {
    lock.lock()
    let proc = process
    let outputPipe = pipe
    let buffer = outputBuffer
    process = nil
    pipe = nil
    outputBuffer = nil
    lock.unlock()

    guard let proc, let outputPipe, let buffer else {
      return EspressoLogParser.summarize([])
    }

    terminate(proc, timeout: 2.0)

    outputPipe.fileHandleForReading.readabilityHandler = nil
    buffer.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
    let output = buffer.string()
    let entries = EspressoLogParser.parse(output)
    return EspressoLogParser.summarize(entries)
  }

  package static func terminate(_ proc: Process, timeout: TimeInterval) {
    proc.terminate()

    let deadline = Date().addingTimeInterval(timeout)
    while proc.isRunning, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.01)
    }

    guard proc.isRunning else { return }
    kill(proc.processIdentifier, SIGKILL)
    proc.waitUntilExit()
  }
}

private final class EspressoPipeOutputBuffer: @unchecked Sendable {
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
