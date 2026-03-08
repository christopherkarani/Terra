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
    MockURLProtocol.allowedHosts = ["example.ai"]
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    var request = URLRequest(url: URL(string: "https://example.ai/v1/chat/completions?api_key=secret")!)
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
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.operationName]?.description, "chat")
    XCTAssertEqual(span.attributes["url.full"]?.description, "https://example.ai/v1/chat/completions")
    XCTAssertEqual(span.attributes["http.url"]?.description, "https://example.ai/v1/chat/completions")
  }

  func testHTTPInstrumentationSkipsExcludedOTLPEndpoint() async throws {
    HTTPAIInstrumentation.resetForTesting()
    defer { HTTPAIInstrumentation.resetForTesting() }

    let exporter = InMemoryExporter()
    let tracerProvider = TracerProviderSdk()
    tracerProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))
    OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
    Terra.install(.init(tracerProvider: tracerProvider, registerProvidersAsGlobal: false))

    let excluded = URL(string: "http://localhost:4318/v1/traces")!
    HTTPAIInstrumentation.install(
      hosts: ["localhost"],
      excludedEndpoints: [excluded]
    )

    MockURLProtocol.responseBody = #"{"ok":true}"#
    MockURLProtocol.allowedHosts = ["localhost"]
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    var request = URLRequest(url: URL(string: "http://localhost:4318/v1/traces?token=sensitive")!)
    request.httpMethod = "POST"
    request.httpBody = Data(#"{"trace":"payload"}"#.utf8)

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
    XCTAssertTrue(spans.isEmpty, "Excluded OTLP endpoint should not be auto-instrumented.")
  }

  func testHTTPInstrumentationCanBeReconfiguredOnSubsequentInstall() async throws {
    HTTPAIInstrumentation.resetForTesting()
    defer { HTTPAIInstrumentation.resetForTesting() }

    let exporter = InMemoryExporter()
    let tracerProvider = TracerProviderSdk()
    tracerProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))
    OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
    Terra.install(.init(tracerProvider: tracerProvider, registerProvidersAsGlobal: false))

    HTTPAIInstrumentation.install(hosts: ["first.example"])
    HTTPAIInstrumentation.install(hosts: ["second.example"])

    MockURLProtocol.responseBody = #"{"model":"response-model"}"#
    MockURLProtocol.allowedHosts = ["second.example"]
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    var request = URLRequest(url: URL(string: "https://second.example/v1/embeddings")!)
    request.httpMethod = "POST"
    request.httpBody = Data(#"{"model":"embedding-model","input":"hello"}"#.utf8)

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
    let span = try XCTUnwrap(spans.first(where: { $0.name.contains("embeddings second.example") }))
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.operationName]?.description, "embeddings")
  }
}

private final class MockURLProtocol: URLProtocol {
  static var responseBody = "{}"
  static var allowedHosts: Set<String> = []

  override class func canInit(with request: URLRequest) -> Bool {
    guard let host = request.url?.host else { return false }
    return allowedHosts.contains(host)
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
