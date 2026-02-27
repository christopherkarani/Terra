import XCTest

@testable import TerraCore

final class TerraInferenceSpanTests: XCTestCase {
  private enum TestFailure: Error, CustomStringConvertible {
    case secret

    var description: String {
      "super-secret-error-message"
    }
  }

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

  func testWithInferenceSpan_privacyNever_omitsExceptionMessage() async throws {
    Terra.install(
      .init(
        privacy: .init(contentPolicy: .never, redaction: .lengthOnly),
        tracerProvider: support.tracerProvider,
        registerProvidersAsGlobal: false
      )
    )

    let request = Terra.InferenceRequest(model: "local/llama-3.2-1b", prompt: "Hello", promptCapture: .optIn)

    do {
      try await Terra.withInferenceSpan(request) { _ in
        throw TestFailure.secret
      }
      XCTFail("Expected error")
    } catch {}

    let span = try XCTUnwrap(support.finishedSpans().first)
    let exception = try XCTUnwrap(span.events.first(where: { $0.name == "exception" }))
    XCTAssertNil(exception.attributes["exception.message"])
    XCTAssertEqual(exception.attributes["exception.type"]?.description, String(reflecting: TestFailure.self))
  }

  func testWithInferenceSpan_privacyAlways_recordsExceptionMessage() async throws {
    Terra.install(
      .init(
        privacy: .init(contentPolicy: .always, redaction: .lengthOnly),
        tracerProvider: support.tracerProvider,
        registerProvidersAsGlobal: false
      )
    )

    let request = Terra.InferenceRequest(model: "local/llama-3.2-1b", prompt: "Hello")

    do {
      try await Terra.withInferenceSpan(request) { _ in
        throw TestFailure.secret
      }
      XCTFail("Expected error")
    } catch {}

    let span = try XCTUnwrap(support.finishedSpans().first)
    let exception = try XCTUnwrap(span.events.first(where: { $0.name == "exception" }))
    XCTAssertEqual(exception.attributes["exception.message"]?.description, TestFailure.secret.description)
    XCTAssertEqual(exception.attributes["exception.type"]?.description, String(reflecting: TestFailure.self))
  }

  func testInstallWithoutTracerProviderClearsOverride() async throws {
    let fallbackSupport = TerraTestSupport()

    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))
    await Terra.withInferenceSpan(.init(model: "model-1")) { _ in }

    Terra.install(.init(tracerProvider: nil, registerProvidersAsGlobal: false))
    await Terra.withInferenceSpan(.init(model: "model-2")) { _ in }

    XCTAssertEqual(support.finishedSpans().count, 1, "Override provider should only receive the first span")
    XCTAssertEqual(fallbackSupport.finishedSpans().count, 1, "Global provider should receive spans after override is cleared")
  }
}
