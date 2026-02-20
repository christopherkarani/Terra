import Foundation
import Testing
import OpenTelemetryApi
@testable import OpenTelemetrySdk
@testable import TerraTraceKit

private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
  let base = FileManager.default.temporaryDirectory
  let dir = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }
  try body(dir)
}

private func makeSpan(name: String, start: Date, end: Date) -> SpanData {
  SpanData(
    traceId: TraceId(),
    spanId: SpanId.random(),
    traceFlags: TraceFlags(),
    traceState: TraceState(),
    resource: Resource(),
    instrumentationScope: InstrumentationScopeInfo(),
    name: name,
    kind: .internal,
    startTime: start,
    endTime: end,
    hasRemoteParent: false,
    hasEnded: true
  )
}

@Test("TraceFileLocator returns only numeric-named trace files")
func traceFileLocatorFiltersInvalidNames() throws {
  try withTemporaryDirectory { dir in
    let tracesDir = dir.appendingPathComponent("traces", isDirectory: true)
    try FileManager.default.createDirectory(at: tracesDir, withIntermediateDirectories: true)
    let good1 = tracesDir.appendingPathComponent("1000")
    let good2 = tracesDir.appendingPathComponent("2000")
    let bad = tracesDir.appendingPathComponent("not-a-number")
    FileManager.default.createFile(atPath: good1.path, contents: Data())
    FileManager.default.createFile(atPath: good2.path, contents: Data())
    FileManager.default.createFile(atPath: bad.path, contents: Data())

    let locator = TraceFileLocator(tracesDirectoryURL: tracesDir)
    let files = try locator.listTraceFiles()
    #expect(files.map(\.fileName) == ["1000", "2000"])
  }
}

@Test("TraceFileLocator parses file timestamps from milliseconds since reference date")
func traceFileLocatorParsesTimestamps() throws {
  try withTemporaryDirectory { dir in
    let tracesDir = dir.appendingPathComponent("traces", isDirectory: true)
    try FileManager.default.createDirectory(at: tracesDir, withIntermediateDirectories: true)
    let ms: UInt64 = 1234
    let fileURL = tracesDir.appendingPathComponent(String(ms))
    FileManager.default.createFile(atPath: fileURL.path, contents: Data())

    let locator = TraceFileLocator(tracesDirectoryURL: tracesDir)
    let files = try locator.listTraceFiles()
    let expectedDate = Date(timeIntervalSinceReferenceDate: TimeInterval(ms) / 1000.0)
    #expect(files.first?.timestamp == expectedDate)
  }
}

@Test("TraceFileReader returns raw file contents and throws on missing file")
func traceFileReaderReadsData() throws {
  try withTemporaryDirectory { dir in
    let tracesDir = dir.appendingPathComponent("traces", isDirectory: true)
    try FileManager.default.createDirectory(at: tracesDir, withIntermediateDirectories: true)
    let fileURL = tracesDir.appendingPathComponent("1000")
    let payload = Data("abc".utf8)
    FileManager.default.createFile(atPath: fileURL.path, contents: payload)

    let file = TraceFileReference(url: fileURL, fileName: "1000", timestamp: Date())
    let reader = TraceFileReader()
    let data = try reader.read(file: file)
    #expect(data == payload)

    let missing = TraceFileReference(
      url: tracesDir.appendingPathComponent("9999"),
      fileName: "9999",
      timestamp: Date()
    )
    #expect(throws: TraceFileError.self) {
      _ = try reader.read(file: missing)
    }
  }
}

@Test("TraceDecoder decodes comma-separated SpanData arrays from file data")
func traceDecoderDecodesSpanDataFromFileData() throws {
  let span = makeSpan(name: "root", start: Date(timeIntervalSince1970: 1), end: Date(timeIntervalSince1970: 2))
  let encoded = try JSONEncoder().encode([span])
  var fileData = Data(encoded)
  fileData.append(Data(",".utf8))

  let decoded = try TraceDecoder().decodeSpans(from: fileData)
  #expect(decoded.count == 1)
}

@Test("TraceLoader reports corrupt files while still loading valid traces")
func traceLoaderReportsCorruptFiles() throws {
  try withTemporaryDirectory { dir in
    let tracesDir = dir.appendingPathComponent("traces", isDirectory: true)
    try FileManager.default.createDirectory(at: tracesDir, withIntermediateDirectories: true)

    let validSpan = makeSpan(name: "root", start: Date(timeIntervalSince1970: 1), end: Date(timeIntervalSince1970: 2))
    let encoded = try JSONEncoder().encode([validSpan])
    var validFileData = Data(encoded)
    validFileData.append(Data(",".utf8))
    FileManager.default.createFile(
      atPath: tracesDir.appendingPathComponent("1000").path,
      contents: validFileData
    )

    FileManager.default.createFile(
      atPath: tracesDir.appendingPathComponent("2000").path,
      contents: Data("not-json,".utf8)
    )

    let loader = TraceLoader(locator: TraceFileLocator(tracesDirectoryURL: tracesDir))
    let result = try loader.loadTracesWithFailures()

    #expect(result.traces.count == 1)
    #expect(result.traces.first?.id.hasPrefix("1000-") == true)
    #expect(result.failures.count == 1)
    #expect(result.failures.first?.file.lastPathComponent == "2000")
  }
}
