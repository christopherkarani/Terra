import Foundation
import Testing
@testable import TraceMacAppUI

@Suite("OllamaLogTraceLoader", .serialized)
struct OllamaLogTraceLoaderTests {
  @Test("parses Ollama GIN access logs into runtime-tagged traces")
  func parsesGinLogsIntoTraces() throws {
    let logsDirectory = try makeTemporaryLogsDirectory()
    defer { try? FileManager.default.removeItem(at: logsDirectory) }

    let logContents = """
    [GIN] 2026/02/18 - 03:02:46 | 200 |   34.828375ms |             ::1 | GET      "/api/tags"
    [GIN] 2026/02/18 - 03:02:59 | 200 | 11.768302041s |             ::1 | POST     "/api/chat"
    [GIN] 2026/02/18 - 03:03:09 | 500 |         1m58s |       127.0.0.1 | POST     "/v1/chat/completions"
    """
    try logContents.write(
      to: logsDirectory.appendingPathComponent("server.log"),
      atomically: true,
      encoding: .utf8
    )

    let result = OllamaLogTraceLoader.loadRecent(maxEntries: 20, logsDirectoryURL: logsDirectory)

    #expect(result.totalEntries == 3)
    #expect(result.traces.count == 3)
    #expect(result.traces.allSatisfy { $0.detectedRuntime == .ollama })
    #expect(result.traces.contains { $0.hasError })
    #expect(result.traces.contains { $0.displayName.contains("POST /v1/chat/completions") })
  }

  @Test("honors maxEntries and supports micro/ms/sec/min duration units")
  func honorsMaxEntriesAndDurationUnits() throws {
    let logsDirectory = try makeTemporaryLogsDirectory()
    defer { try? FileManager.default.removeItem(at: logsDirectory) }

    let logContents = """
    [GIN] 2026/02/18 - 03:00:00 | 200 |      96.083µs |       127.0.0.1 | GET      "/api/version"
    [GIN] 2026/02/18 - 03:00:01 | 200 |     110.583ms |       127.0.0.1 | GET      "/api/tags"
    [GIN] 2026/02/18 - 03:00:02 | 200 |  10.500000000s |       127.0.0.1 | POST     "/api/chat"
    [GIN] 2026/02/18 - 03:00:03 | 200 |         1m58s |       127.0.0.1 | POST     "/v1/chat/completions"
    """
    try logContents.write(
      to: logsDirectory.appendingPathComponent("server-2.log"),
      atomically: true,
      encoding: .utf8
    )

    let result = OllamaLogTraceLoader.loadRecent(maxEntries: 2, logsDirectoryURL: logsDirectory)

    #expect(result.totalEntries == 4)
    #expect(result.traces.count == 2)
    #expect(result.traces[0].displayName.contains("POST /api/chat"))
    #expect(result.traces[1].displayName.contains("POST /v1/chat/completions"))
    #expect(abs(result.traces[1].duration - 118) < 0.001)
  }

  private func makeTemporaryLogsDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("OllamaLogTraceLoaderTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}
