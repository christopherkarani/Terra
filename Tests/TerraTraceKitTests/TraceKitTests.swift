import Foundation
import Testing
import OpenTelemetryApi
@testable import OpenTelemetrySdk
@testable import TerraTraceKit

// MARK: - Test Helpers

private func makeSpan(
  name: String,
  traceId: TraceId = TraceId(),
  spanId: SpanId = SpanId.random(),
  parentSpanId: SpanId? = nil,
  start: Date = Date(timeIntervalSince1970: 1000),
  end: Date = Date(timeIntervalSince1970: 1001),
  status: Status = .unset
) -> SpanData {
  var span = SpanData(
    traceId: traceId,
    spanId: spanId,
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
  if let parentSpanId {
    span = span.settingParentSpanId(parentSpanId)
  }
  span = span.settingStatus(status)
  return span
}

/// Writes span data as the persistence exporter format (JSON array + trailing comma).
private func writeSpanFile(spans: [SpanData], to url: URL) throws {
  let data = try JSONEncoder().encode(spans)
  var fileData = data
  fileData.append(Data(",".utf8))
  try fileData.write(to: url)
}

// MARK: - TraceFileLocator Tests

@Test("TraceFileLocator returns empty array for non-existent directory")
func locatorReturnsEmptyForMissingDirectory() throws {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  let locator = TraceFileLocator(tracesDirectoryURL: url)
  let files = try locator.listTraceFiles()
  #expect(files.isEmpty)
}

@Test("TraceFileLocator excludes non-numeric filenames")
func locatorExcludesNonNumericFiles() throws {
  let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }

  // Create a numeric file (valid trace) and a non-numeric file
  try Data("[]".utf8).write(to: dir.appendingPathComponent("1000000"))
  try Data("[]".utf8).write(to: dir.appendingPathComponent("readme.txt"))
  try Data("[]".utf8).write(to: dir.appendingPathComponent("abc123"))

  let locator = TraceFileLocator(tracesDirectoryURL: dir)
  let files = try locator.listTraceFiles()
  #expect(files.count == 1)
  #expect(files[0].fileName == "1000000")
}

@Test("TraceFileLocator returns files sorted by timestamp ascending")
func locatorSortsByTimestamp() throws {
  let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }

  try Data("[]".utf8).write(to: dir.appendingPathComponent("3000"))
  try Data("[]".utf8).write(to: dir.appendingPathComponent("1000"))
  try Data("[]".utf8).write(to: dir.appendingPathComponent("2000"))

  let locator = TraceFileLocator(tracesDirectoryURL: dir)
  let files = try locator.listTraceFiles()
  #expect(files.map(\.fileName) == ["1000", "2000", "3000"])
}

// MARK: - TraceFileNameParser Tests

@Test("TraceFileNameParser extracts timestamp from numeric prefix")
func parserExtractsTimestamp() {
  let ts = TraceFileNameParser.timestamp(from: "123456")
  #expect(ts != nil)
  let expected = Date(timeIntervalSinceReferenceDate: 123.456)
  #expect(ts == expected)
}

@Test("TraceFileNameParser handles composite filename with non-digit suffix")
func parserHandlesCompositeFilename() {
  let ts = TraceFileNameParser.timestamp(from: "999000-abcdef1234")
  #expect(ts != nil)
  let expected = Date(timeIntervalSinceReferenceDate: 999.0)
  #expect(ts == expected)
}

@Test("TraceFileNameParser returns nil for non-digit filename")
func parserReturnsNilForNonDigits() {
  let ts = TraceFileNameParser.timestamp(from: "hello-world")
  #expect(ts == nil)
}

@Test("TraceFileNameParser returns nil for empty string")
func parserReturnsNilForEmpty() {
  let ts = TraceFileNameParser.timestamp(from: "")
  #expect(ts == nil)
}

// MARK: - Trace Model Tests

@Test("Trace.init throws emptySpans for empty array")
func traceRejectsEmptySpans() {
  #expect(throws: TraceModelError.emptySpans) {
    _ = try Trace(fileName: "123456", spans: [])
  }
}

@Test("Trace.init throws mismatchedTraceIds when spans have different trace IDs")
func traceRejectsMismatchedIds() {
  let span1 = makeSpan(name: "a", traceId: TraceId.random())
  let span2 = makeSpan(name: "b", traceId: TraceId.random())
  #expect(throws: TraceModelError.mismatchedTraceIds) {
    _ = try Trace(fileName: "123456", spans: [span1, span2])
  }
}

@Test("Trace.init throws duplicateSpanIds when spans reuse the same span ID")
func traceRejectsDuplicateSpanIds() {
  let traceId = TraceId.random()
  let duplicateSpanID = SpanId.random()
  let span1 = makeSpan(name: "a", traceId: traceId, spanId: duplicateSpanID)
  let span2 = makeSpan(name: "b", traceId: traceId, spanId: duplicateSpanID)
  #expect(throws: TraceModelError.duplicateSpanIds) {
    _ = try Trace(fileName: "123456", spans: [span1, span2])
  }
}

@Test("Trace.init throws invalidFileName for non-numeric name")
func traceRejectsInvalidFileName() {
  let span = makeSpan(name: "root")
  #expect(throws: TraceModelError.invalidFileName) {
    _ = try Trace(fileName: "not-a-number", spans: [span])
  }
}

@Test("Trace computes correct start and end times from spans")
func traceComputesBoundariesCorrectly() throws {
  let traceId = TraceId()
  let early = makeSpan(
    name: "early",
    traceId: traceId,
    start: Date(timeIntervalSince1970: 100),
    end: Date(timeIntervalSince1970: 200)
  )
  let late = makeSpan(
    name: "late",
    traceId: traceId,
    start: Date(timeIntervalSince1970: 150),
    end: Date(timeIntervalSince1970: 300)
  )

  let trace = try Trace(fileName: "123456", spans: [late, early])
  #expect(trace.startTime == early.startTime)
  #expect(trace.endTime == late.endTime)
  #expect(trace.duration == 200.0)
}

// MARK: - TraceLoader Tests

@Test("TraceLoader returns empty for empty directory")
func loaderReturnsEmptyForEmptyDir() throws {
  let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }

  let locator = TraceFileLocator(tracesDirectoryURL: dir)
  let loader = TraceLoader(locator: locator)
  let result = try loader.loadTracesWithFailures()
  #expect(result.traces.isEmpty)
  #expect(result.failures.isEmpty)
}

@Test("TraceLoader loads valid traces and reports bad files as failures")
func loaderHandlesMixedFiles() throws {
  let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }

  // Write a valid trace file
  let traceId = TraceId()
  let span = makeSpan(name: "root", traceId: traceId)
  try writeSpanFile(spans: [span], to: dir.appendingPathComponent("1000000"))

  // Write a corrupt file
  try Data("this is not json,".utf8).write(to: dir.appendingPathComponent("2000000"))

  let locator = TraceFileLocator(tracesDirectoryURL: dir)
  let loader = TraceLoader(locator: locator)
  let result = try loader.loadTracesWithFailures()

  #expect(result.traces.count == 1)
  #expect(result.traces[0].spans[0].name == "root")
  #expect(result.failures.count == 1)
  #expect(result.failures[0].file.lastPathComponent == "2000000")
  #expect(result.loadedFileCount == 2)
  #expect(result.totalFileCount == 2)
}

@Test("TraceLoader maxFiles loads only the newest files")
func loaderRespectsMaxFilesNewestFirst() throws {
  let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }

  let traceIdOld = TraceId()
  let traceIdNew = TraceId()
  try writeSpanFile(spans: [makeSpan(name: "old", traceId: traceIdOld)], to: dir.appendingPathComponent("1000"))
  try writeSpanFile(spans: [makeSpan(name: "new", traceId: traceIdNew)], to: dir.appendingPathComponent("2000"))

  let loader = TraceLoader(locator: TraceFileLocator(tracesDirectoryURL: dir))
  let result = try loader.loadTracesWithFailures(maxFiles: 1)
  #expect(result.traces.count == 1)
  #expect(result.traces.first?.spans.first?.name == "new")
  #expect(result.loadedFileCount == 1)
  #expect(result.totalFileCount == 2)
}

@Test("TraceLoader returns empty for non-existent directory")
func loaderReturnsEmptyForMissingDir() throws {
  let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  let locator = TraceFileLocator(tracesDirectoryURL: dir)
  let loader = TraceLoader(locator: locator)
  let result = try loader.loadTracesWithFailures()
  #expect(result.traces.isEmpty)
  #expect(result.failures.isEmpty)
}

@Test("TraceLoader reports oversized trace files as failures")
func loaderReportsOversizedFileFailures() throws {
  let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }

  let oversized = Data(repeating: 0x41, count: 2048)
  try oversized.write(to: dir.appendingPathComponent("1000000"))

  let loader = TraceLoader(
    locator: TraceFileLocator(tracesDirectoryURL: dir),
    reader: TraceFileReader(maxFileSizeBytes: 256)
  )
  let result = try loader.loadTracesWithFailures()

  #expect(result.traces.isEmpty)
  #expect(result.failures.count == 1)
  if let failure = result.failures.first {
    if case let TraceFileError.fileTooLarge(_, actualBytes, maxBytes) = failure.error {
      #expect(actualBytes == 2048)
      #expect(maxBytes == 256)
    } else {
      Issue.record("Expected fileTooLarge failure, got \(failure.error)")
    }
  }
}
