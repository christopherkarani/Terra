import XCTest
@testable import TerraCore
@testable import TerraTraceKit

final class TerraE2ETests: XCTestCase {
  private var support: TerraTestSupport!

  override func setUp() {
    super.setUp()
    support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))
  }

  override func tearDown() {
    support.reset()
    super.tearDown()
  }

  func testSpanCreateExportLoadParseFlow() async throws {
    await Terra.withInferenceSpan(.init(model: "e2e-model", prompt: "hello")) { _ in }

    let spans = support.finishedSpans()
    XCTAssertEqual(spans.count, 1)

    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("TerraE2ETests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fileURL = tempDir.appendingPathComponent("1000", isDirectory: false)
    let encoded = try JSONEncoder().encode(spans)
    var persisted = Data(encoded)
    persisted.append(Data(",".utf8))
    try persisted.write(to: fileURL)

    let loader = TraceLoader(locator: TraceFileLocator(tracesDirectoryURL: tempDir))
    let loaded = try loader.loadTracesWithFailures()
    XCTAssertEqual(loaded.failures.count, 0)
    XCTAssertEqual(loaded.traces.count, 1)
    XCTAssertEqual(loaded.traces.first?.spans.first?.name, Terra.SpanNames.inference)
  }
}
