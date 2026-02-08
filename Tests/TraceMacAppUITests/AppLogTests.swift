import Foundation
import Testing
@testable import TraceMacAppUI

@Suite("AppLog Tests")
struct AppLogTests {
  private let tempDirectory: URL

  init() throws {
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("AppLogTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  private func makeLogURL(_ name: String = "test.log") -> URL {
    tempDirectory.appendingPathComponent(name, isDirectory: false)
  }

  private func cleanup() {
    try? FileManager.default.removeItem(at: tempDirectory)
  }

  @Test("Log file is created on first write")
  func logFileCreatedOnFirstWrite() async throws {
    let logURL = makeLogURL()
    let log = AppLog(fileURL: logURL)

    #expect(!FileManager.default.fileExists(atPath: logURL.path))

    await log.info("hello")

    #expect(FileManager.default.fileExists(atPath: logURL.path))
    cleanup()
  }

  @Test("info() writes line containing [INFO]")
  func infoWritesINFOTag() async throws {
    let logURL = makeLogURL()
    let log = AppLog(fileURL: logURL)

    await log.info("test message")

    let contents = try String(contentsOf: logURL, encoding: .utf8)
    #expect(contents.contains("[INFO]"))
    #expect(contents.contains("test message"))
    cleanup()
  }

  @Test("error() writes line containing [ERROR]")
  func errorWritesERRORTag() async throws {
    let logURL = makeLogURL()
    let log = AppLog(fileURL: logURL)

    await log.error("something broke")

    let contents = try String(contentsOf: logURL, encoding: .utf8)
    #expect(contents.contains("[ERROR]"))
    #expect(contents.contains("something broke"))
    cleanup()
  }

  @Test("Written lines contain ISO8601 timestamps")
  func linesContainISO8601Timestamps() async throws {
    let logURL = makeLogURL()
    let log = AppLog(fileURL: logURL)

    await log.info("timestamp check")

    let contents = try String(contentsOf: logURL, encoding: .utf8)
    // ISO8601 timestamps contain a 'T' separator and end with 'Z'
    let line = contents.trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(line.contains("T"))
    #expect(line.contains("Z"))
    cleanup()
  }

  @Test("Log rotation renames original to .1 when exceeding 5MB")
  func logRotationRenamesFile() async throws {
    let logURL = makeLogURL()
    let log = AppLog(fileURL: logURL)

    // Create a log file larger than 5MB (maxLogSize)
    let fm = FileManager.default
    try fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let largeData = Data(repeating: 65, count: 5_000_001) // Just over 5MB
    fm.createFile(atPath: logURL.path, contents: largeData)

    // Write another line to trigger rotation
    await log.info("after rotation")

    let backup1Path = logURL.path.appending(".1")
    #expect(fm.fileExists(atPath: backup1Path), "Original log should be renamed to .1")
    #expect(fm.fileExists(atPath: logURL.path), "New log file should be created")

    // The new log should contain only the post-rotation message
    let newContents = try String(contentsOf: logURL, encoding: .utf8)
    #expect(newContents.contains("after rotation"))

    // The backup should contain the original large data
    let backupAttrs = try fm.attributesOfItem(atPath: backup1Path)
    let backupSize = backupAttrs[.size] as? UInt64 ?? 0
    #expect(backupSize >= 5_000_001)

    cleanup()
  }
}
