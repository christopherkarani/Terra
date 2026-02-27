import Foundation
import InMemoryExporter
import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest
@testable import TerraCore
@testable import TerraHTTPInstrument

final class HTTPIntegrationTests: XCTestCase {
  func testHTTPInstrumentationCapturesRequestAndResponseGenAIAttributes() async throws {
    HTTPAIInstrumentation.resetForTesting()
    defer { HTTPAIInstrumentation.resetForTesting() }

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

    var chatRequest = URLRequest(url: URL(string: "https://example.ai/v1/chat/completions")!)
    chatRequest.httpMethod = "POST"
    chatRequest.httpBody = Data(#"{"model":"request-model","max_tokens":42}"#.utf8)
    chatRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    try await runDataTask(session: session, request: chatRequest)

    MockURLProtocol.responseBody = #"{"model":"embed-response","usage":{"prompt_tokens":2}}"#
    var embeddingsRequest = URLRequest(url: URL(string: "https://example.ai/v1/embeddings")!)
    embeddingsRequest.httpMethod = "POST"
    embeddingsRequest.httpBody = Data(#"{"model":"text-embedding-3-small"}"#.utf8)
    embeddingsRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    try await runDataTask(session: session, request: embeddingsRequest)

    tracerProvider.forceFlush()

    let spans = exporter.getFinishedSpanItems()
    let chatSpan = try XCTUnwrap(spans.first(where: { $0.name.contains("chat") }))
    XCTAssertEqual(chatSpan.attributes[Terra.Keys.GenAI.requestModel]?.description, "request-model")
    XCTAssertEqual(chatSpan.attributes[Terra.Keys.GenAI.requestMaxTokens]?.description, "42")
    XCTAssertEqual(chatSpan.attributes[Terra.Keys.GenAI.operationName]?.description, "chat")
    XCTAssertNil(chatSpan.attributes["url.full"])

    let embeddingsSpan = try XCTUnwrap(spans.first(where: { $0.name.contains("embeddings") }))
    XCTAssertEqual(embeddingsSpan.attributes[Terra.Keys.GenAI.requestModel]?.description, "text-embedding-3-small")
    XCTAssertEqual(embeddingsSpan.attributes[Terra.Keys.GenAI.operationName]?.description, "embeddings")
  }
}

private func runDataTask(session: URLSession, request: URLRequest) async throws {
  try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
    let task = session.dataTask(with: request) { _, _, error in
      if let error {
        continuation.resume(throwing: error)
      } else {
        continuation.resume(returning: ())
      }
    }
    task.resume()
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
