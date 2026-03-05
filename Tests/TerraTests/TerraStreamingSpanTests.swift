import XCTest
@testable import TerraCore

final class TerraStreamingSpanTests: XCTestCase {
  private var support: TerraTestSupport!

  override func setUp() {
    super.setUp()
    support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))
  }

  override func tearDown() {
    support.reset()
    support = nil
    super.tearDown()
  }

  func testWithStreamingInferenceSpan_recordsFirstTokenAndThroughput() async throws {
    let request = Terra.StreamingRequest(model: "local/model")

    await Terra.withStreamingInferenceSpan(request) { stream in
      stream.recordChunk()
      stream.recordToken()
      stream.recordToken()
    }

    let span = try XCTUnwrap(support.finishedSpans().first)
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.streamChunkCount]?.description, "1")
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.streamOutputTokens]?.description, "2")
    XCTAssertNotNil(span.attributes[Terra.Keys.Terra.streamTimeToFirstTokenMs])
    XCTAssertNotNil(span.attributes[Terra.Keys.Terra.streamTokensPerSecond])
    XCTAssertTrue(span.events.contains { $0.name == Terra.Keys.Terra.streamFirstTokenEvent })
  }

  func testStreamRun_setsRuntimeAndChunkAttributes() async throws {
    _ = await Terra
      .stream(model: "local/model", prompt: "hello")
      .runtime("foundation_models")
      .execute { trace in
        trace.chunk(tokens: 3)
      }

    let span = try XCTUnwrap(support.finishedSpans().first)
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.streamChunkCount]?.description, "1")
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.streamOutputTokens]?.description, "3")
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.runtime]?.description, "foundation_models")
  }
}
