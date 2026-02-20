import XCTest

@testable import TerraCore

final class TerraInferenceSpanTests: XCTestCase {
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

  func testWithInferenceSpan_createsSpan_withExpectedNameKindAndAttributes() async throws {
    let request = Terra.InferenceRequest(
      model: "local/llama-3.2-1b",
      prompt: "Hello",
      maxOutputTokens: 16,
      temperature: 0.7,
      stream: false
    )

    await Terra.withInferenceSpan(request) { _ in
      // no-op: Terra should still create/end the span
    }

    let spans = support.finishedSpans()
    XCTAssertEqual(spans.count, 1)

    guard let span = spans.first else {
      XCTFail("Missing span")
      return
    }

    XCTAssertEqual(span.name, Terra.SpanNames.inference)
    XCTAssertEqual(span.kind, .internal)

    XCTAssertEqual(
      span.attributes[Terra.Keys.GenAI.operationName]?.description,
      Terra.OperationName.inference.rawValue
    )
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.requestModel]?.description, "local/llama-3.2-1b")
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.requestMaxTokens]?.description, "16")
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.requestTemperature]?.description, "0.7")
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.requestStream]?.description, "false")
  }

  func testWithInferenceSpan_cancellationDoesNotMarkSpanAsError() async throws {
    let request = Terra.InferenceRequest(model: "local/llama-3.2-1b", prompt: "Hello")

    do {
      try await Terra.withInferenceSpan(request) { _ in
        throw CancellationError()
      }
      XCTFail("Expected CancellationError")
    } catch is CancellationError {
      // Expected.
    }

    let span = try XCTUnwrap(support.finishedSpans().first)
    XCTAssertFalse(span.status.isError)
  }
}
