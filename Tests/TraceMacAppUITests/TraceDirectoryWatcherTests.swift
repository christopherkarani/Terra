import Foundation
import Testing
@testable import TraceMacAppUI

@Suite("TraceDirectoryWatcher Tests")
struct TraceDirectoryWatcherTests {
  private let tempDirectory: URL

  init() throws {
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TraceDirectoryWatcherTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  private func cleanup() {
    try? FileManager.default.removeItem(at: tempDirectory)
  }

  @Test("Watcher can start and stop without errors")
  func startAndStopSucceeds() throws {
    let watcher = TraceDirectoryWatcher(directoryURL: tempDirectory) {}
    try watcher.start()
    watcher.stop()
    cleanup()
  }

  @Test("Writing a file triggers the onChange callback")
  @MainActor
  func writingFileTriggerCallback() async throws {
    try await confirmation(expectedCount: 1) { confirmed in
      let watcher = TraceDirectoryWatcher(directoryURL: tempDirectory) {
        confirmed()
      }
      try watcher.start()

      // Write a file into the watched directory to trigger the event.
      let fileURL = tempDirectory.appendingPathComponent("trigger.txt", isDirectory: false)
      try Data("hello".utf8).write(to: fileURL, options: .atomic)

      // Wait long enough for the 250ms debounce + dispatch to fire.
      try await Task.sleep(for: .milliseconds(600))
      watcher.stop()
    }
    cleanup()
  }

  @Test("Starting when already started is a no-op")
  func doubleStartIsNoOp() throws {
    let watcher = TraceDirectoryWatcher(directoryURL: tempDirectory) {}
    try watcher.start()
    // Second start should not throw or create a duplicate source.
    try watcher.start()
    watcher.stop()
    cleanup()
  }

  @Test("Stop cleans up resources")
  func stopCleansUpResources() throws {
    let watcher = TraceDirectoryWatcher(directoryURL: tempDirectory) {}
    try watcher.start()
    watcher.stop()
    // Stopping again should be safe (idempotent).
    watcher.stop()
    cleanup()
  }
}
