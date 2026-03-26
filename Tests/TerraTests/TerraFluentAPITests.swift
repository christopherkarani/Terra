import XCTest

@testable import TerraCore

final class TerraFluentAPITests: XCTestCase {
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

  func testInferenceFluentRun_createsInferenceSpan() async throws {
    let result = await Terra.inference(model: "local/fluent", prompt: "hello").execute {
      "ok"
    }

    XCTAssertEqual(result, "ok")
    let span = try XCTUnwrap(support.finishedSpans().first)
    XCTAssertEqual(span.name, Terra.SpanNames.inference)
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.requestModel]?.description, "local/fluent")
  }

  func testInferenceFluentRun_appliesMetadataAttributes() async throws {
    await Terra
      .inference(model: "local/fluent", prompt: "hello")
      .includeContent()
      .provider("openai-compatible")
      .runtime("mlx")
      .responseModel("local/fluent@v2")
      .tokens(input: 10, output: 5)
      .attribute(.init("terra.custom.enabled"), true)
      .execute { }

    let span = try XCTUnwrap(support.finishedSpans().first)
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.providerName]?.description, "openai-compatible")
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.runtime]?.description, "mlx")
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.responseModel]?.description, "local/fluent@v2")
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.usageInputTokens]?.description, "10")
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.usageOutputTokens]?.description, "5")
    XCTAssertEqual(span.attributes["terra.custom.enabled"]?.description, "true")
  }

  func testStreamingFluentRun_traceContextRecordsChunkAndTokens() async throws {
    await Terra.stream(model: "local/fluent-stream").execute { trace in
      trace.chunk(tokens: 3).outputTokens(4)
    }

    let span = try XCTUnwrap(support.finishedSpans().first)
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.requestStream]?.description, "true")
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.streamChunkCount]?.description, "1")
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.streamOutputTokens]?.description, "4")
  }
}
