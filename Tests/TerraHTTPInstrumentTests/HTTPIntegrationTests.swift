import Foundation
import InMemoryExporter
import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest
@testable import TerraCore
@testable import TerraHTTPInstrument

final class HTTPIntegrationTests: XCTestCase {
  func testTestingIsolationLockSupportsAsyncThreadHop() async {
    Terra.lockTestingIsolation()

    let crossThreadUnlock = expectation(description: "cross-thread unlock")
    DispatchQueue.global().async {
      Terra.unlockTestingIsolation()
      crossThreadUnlock.fulfill()
    }
    await fulfillment(of: [crossThreadUnlock], timeout: 1.0)

    let secondAcquire = expectation(description: "second lock acquire")
    DispatchQueue.global().async {
      Terra.lockTestingIsolation()
      Terra.unlockTestingIsolation()
      secondAcquire.fulfill()
    }

    await fulfillment(of: [secondAcquire], timeout: 1.0)
  }

  func testHTTPInstrumentationCapturesRequestAndResponseGenAIAttributes() async throws {
    Terra.lockTestingIsolation()
    let previousTracerProvider = OpenTelemetry.instance.tracerProvider
    Terra.resetOpenTelemetryForTesting()
    HTTPAIInstrumentation.resetForTesting()
    defer {
      HTTPAIInstrumentation.resetForTesting()
      Terra.resetOpenTelemetryForTesting()
      OpenTelemetry.registerTracerProvider(tracerProvider: previousTracerProvider)
      Terra.unlockTestingIsolation()
    }

    let exporter = InMemoryExporter()
    let tracerProvider = TracerProviderSdk()
    tracerProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))
    OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
    Terra.install(.init(tracerProvider: tracerProvider, registerProvidersAsGlobal: false))

    HTTPAIInstrumentation.install(hosts: ["example.ai"])

    MockURLProtocol.responseBody = #"{"model":"response-model","usage":{"prompt_tokens":3,"completion_tokens":5}}"#
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    var request = URLRequest(url: URL(string: "https://example.ai/v1/chat/completions?key=secret-token")!)
    request.httpMethod = "POST"
    request.httpBody = Data(#"{"model":"request-model","max_tokens":42}"#.utf8)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let task = session.dataTask(with: request) { _, _, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
      task.resume()
    }
    tracerProvider.forceFlush()

    let spans = exporter.getFinishedSpanItems()
    let span = try XCTUnwrap(spans.first(where: { $0.name.contains("chat") }))
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.requestModel]?.description, "request-model")
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.requestMaxTokens]?.description, "42")
    XCTAssertEqual(span.attributes["http.url"]?.description, "https://example.ai")
    XCTAssertEqual(span.attributes["url.full"]?.description, "https://example.ai")
    XCTAssertFalse(span.attributes.values.contains { $0.description.contains("secret-token") })
  }

  // P0-4: receivedResponse must populate gen_ai.response.model and usage
  // tokens from the body delivered via the dataTask completion-handler path.
  func testReceivedResponsePopulatesGenAIResponseAttributesFromBody() async throws {
    Terra.lockTestingIsolation()
    let previousTracerProvider = OpenTelemetry.instance.tracerProvider
    Terra.resetOpenTelemetryForTesting()
    HTTPAIInstrumentation.resetForTesting()
    defer {
      HTTPAIInstrumentation.resetForTesting()
      Terra.resetOpenTelemetryForTesting()
      OpenTelemetry.registerTracerProvider(tracerProvider: previousTracerProvider)
      Terra.unlockTestingIsolation()
    }

    let exporter = InMemoryExporter()
    let tracerProvider = TracerProviderSdk()
    tracerProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))
    OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
    Terra.install(.init(tracerProvider: tracerProvider, registerProvidersAsGlobal: false))

    let config = HTTPAIInstrumentation.makeConfiguration(
      hosts: ["example.ai"],
      openClawGatewayHosts: [],
      openClawMode: "disabled"
    )
    let tracer = tracerProvider.get(instrumentationName: "http-response-test")
    let activeSpan = tracer.spanBuilder(spanName: "chat example.ai").startSpan()
    let response = HTTPURLResponse(
      url: URL(string: "https://example.ai/v1/chat/completions")!,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    let body = Data(
      #"{"id":"chatcmpl-1","model":"gpt-4o-2024-08-06","usage":{"prompt_tokens":11,"completion_tokens":23,"total_tokens":34}}"#.utf8
    )

    config.receivedResponse?(response, body, activeSpan)
    activeSpan.end()
    tracerProvider.forceFlush()

    let spans = exporter.getFinishedSpanItems()
    let span = try XCTUnwrap(spans.first(where: { $0.name.contains("chat") }))
    XCTAssertEqual(
      span.attributes[Terra.Keys.GenAI.responseModel]?.description,
      "gpt-4o-2024-08-06"
    )
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.usageInputTokens]?.description, "11")
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.usageOutputTokens]?.description, "23")
  }

  // P0-3: Successful streaming responses must emit terra.stream.completed = true
  // and surface output tokens parsed from the SSE body.
  func testStreamingSuccessSetsStreamCompletedTrue() async throws {
    Terra.lockTestingIsolation()
    let previousTracerProvider = OpenTelemetry.instance.tracerProvider
    Terra.resetOpenTelemetryForTesting()
    HTTPAIInstrumentation.resetForTesting()
    defer {
      HTTPAIInstrumentation.resetForTesting()
      Terra.resetOpenTelemetryForTesting()
      OpenTelemetry.registerTracerProvider(tracerProvider: previousTracerProvider)
      Terra.unlockTestingIsolation()
    }

    let exporter = InMemoryExporter()
    let tracerProvider = TracerProviderSdk()
    tracerProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))
    OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
    Terra.install(.init(tracerProvider: tracerProvider, registerProvidersAsGlobal: false))

    let config = HTTPAIInstrumentation.makeConfiguration(
      hosts: ["example.ai"],
      openClawGatewayHosts: [],
      openClawMode: "disabled"
    )

    var request = URLRequest(url: URL(string: "https://example.ai/v1/chat/completions")!)
    request.httpMethod = "POST"
    request.httpBody = Data(
      #"{"model":"gpt-4o","messages":[{"role":"user","content":"hi"}],"stream":true}"#.utf8
    )
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

    let tracer = tracerProvider.get(instrumentationName: "http-stream-test")
    let builder = tracer.spanBuilder(spanName: "chat example.ai").setSpanKind(spanKind: .client)
    config.spanCustomization?(request, builder)
    let activeSpan = builder.startSpan()
    config.injectCustomHeaders?(&request, activeSpan)
    config.createdRequest?(request, activeSpan)

    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "text/event-stream"]
    )!
    let body = Data("""
      data: {"choices":[{"delta":{"content":"hi"}}]}\n\n\
      data: {"choices":[{"delta":{"content":" there"}}]}\n\n\
      data: {"usage":{"completion_tokens":5}}\n\n\
      data: [DONE]\n\n
      """.utf8)

    config.receivedResponse?(response, body, activeSpan)
    activeSpan.end()
    tracerProvider.forceFlush()

    let spans = exporter.getFinishedSpanItems()
    let span = try XCTUnwrap(spans.first(where: { $0.name.contains("chat") }))
    XCTAssertEqual(
      span.attributes["terra.stream.completed"]?.description,
      "true",
      "Successful streaming response must mark terra.stream.completed = true"
    )
    XCTAssertEqual(
      span.attributes[Terra.Keys.GenAI.usageOutputTokens]?.description,
      "5",
      "Streaming success path must surface output tokens parsed from the SSE body"
    )
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.streamOutputTokens]?.description, "5")
    XCTAssertNotNil(span.attributes[Terra.Keys.Terra.streamChunkCount])
  }

  // P0-3 (Approach B): the streaming observer is summary-only.
  // recordChunk(for:data:) is internal-only; the public auto-instrumented
  // surface never publishes per-chunk attributes itself — it parses the
  // completed body once via recordCompletedStreamBody(_:span:).
  func testStreamingObserverIsSummaryOnly_recordChunkRemovedOrDocumented() {
    let observer = HTTPAIStreamingObserver.shared

    // The summary-emit method must exist and be safely callable on an
    // unregistered request (it should no-op rather than crash).
    let request = URLRequest(url: URL(string: "https://example.ai/v1/chat/completions")!)
    let body = Data(#"data: {"usage":{"completion_tokens":3}}\n\n"#.utf8)
    observer.recordCompletedStreamBody(for: request, data: body)
  }
}

private final class MockURLProtocol: URLProtocol {
  static var responseBody = "{}"

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "example.ai"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(Self.responseBody.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
