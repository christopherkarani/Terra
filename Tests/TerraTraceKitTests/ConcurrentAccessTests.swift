import Foundation
import OpenTelemetryApi
import Testing
@testable import OpenTelemetrySdk
@testable import TerraTraceKit

@Suite("TraceKit ConcurrentAccessTests", .serialized)
struct ConcurrentAccessTests {
  @Test("TraceLoader handles concurrent loads without crashing")
  func concurrentLoadsAreStable() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ConcurrentAccessTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let traceId = TraceId()
    var span = SpanData(
      traceId: traceId,
      spanId: SpanId(),
      traceFlags: TraceFlags(),
      traceState: TraceState(),
      resource: Resource(),
      instrumentationScope: InstrumentationScopeInfo(),
      name: "root",
      kind: .internal,
      startTime: Date(timeIntervalSince1970: 1),
      endTime: Date(timeIntervalSince1970: 2),
      hasRemoteParent: false,
      hasEnded: true
    )
    span = span.settingStatus(.ok)
    let payload = try JSONEncoder().encode([span])

    for i in 0..<20 {
      var data = payload
      data.append(Data(",".utf8))
      try data.write(to: tempDir.appendingPathComponent("\(1000 + i)"))
    }

    let loader = TraceLoader(locator: TraceFileLocator(tracesDirectoryURL: tempDir))
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<20 {
        group.addTask {
          _ = try? loader.loadTracesWithFailures()
        }
      }
    }

    let result = try loader.loadTracesWithFailures()
    #expect(result.traces.count == 20)
    #expect(result.failures.isEmpty)
  }
}
