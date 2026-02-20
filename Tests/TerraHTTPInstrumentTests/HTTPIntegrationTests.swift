import Foundation
import InMemoryExporter
import OpenTelemetryApi
import OpenTelemetrySdk
import Testing
@testable import TerraCore
@testable import TerraHTTPInstrument

@Suite("HTTPIntegrationTests", .serialized)
struct HTTPIntegrationTests {
  @Test("HTTP instrumentation captures request and response GenAI attributes")
  func capturesAIRequestAndResponseAttributes() async throws {
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

    var request = URLRequest(url: URL(string: "https://example.ai/v1/chat/completions")!)
    request.httpMethod = "POST"
    request.httpBody = Data(#"{"model":"request-model","max_tokens":42}"#.utf8)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    _ = try await session.data(for: request)
    tracerProvider.forceFlush()

    let spans = exporter.getFinishedSpanItems()
    let span = try #require(spans.first(where: { $0.name.contains("chat") }))
    #expect(span.attributes[Terra.Keys.GenAI.requestModel]?.description == "request-model")
    #expect(span.attributes[Terra.Keys.GenAI.requestMaxTokens]?.description == "42")
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
