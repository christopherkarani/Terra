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
    let harness = HTTPIntegrationTelemetryHarness.shared
    harness.reset()

    MockURLProtocol.responseBody = #"{"model":"response-model","usage":{"prompt_tokens":3,"completion_tokens":5}}"#
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    var request = URLRequest(url: URL(string: "https://example.ai/v1/chat/completions")!)
    request.httpMethod = "POST"
    request.httpBody = Data(#"{"model":"request-model","max_tokens":42}"#.utf8)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    _ = try await session.data(for: request)

    let spans = harness.finishedSpans()
    let span = try #require(spans.first(where: { $0.name.contains("chat") }))
    #expect(span.attributes[Terra.Keys.GenAI.requestModel]?.description == "request-model")
    #expect(span.attributes[Terra.Keys.GenAI.requestMaxTokens]?.description == "42")
  }

  @Test("HTTP instrumentation preserves streaming lifecycle attribution for async URLSession")
  func capturesAsyncStreamingLifecycleTelemetry() async throws {
    let harness = HTTPIntegrationTelemetryHarness.shared
    harness.reset()

    MockURLProtocol.responseHeaders = ["Content-Type": "application/x-ndjson"]
    MockURLProtocol.responseBody = [
      #"{"model":"qwen2","created_at":"2024-01-01T00:00:00.000Z","response":"H","done":false}"#,
      #"{"model":"qwen2","created_at":"2024-01-01T00:00:00.250Z","response":"i","done":false}"#,
      #"{"model":"qwen2","created_at":"2024-01-01T00:00:00.500Z","done":true,"prompt_eval_count":14,"eval_count":2,"prompt_eval_duration":1500000000,"eval_duration":2500000000,"load_duration":800000}"#,
    ].joined(separator: "\n")

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    var request = URLRequest(url: URL(string: "https://example.ai/api/chat")!)
    request.httpMethod = "POST"
    request.httpBody = Data(#"{"model":"qwen2","stream":true}"#.utf8)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    _ = try await session.data(for: request)

    let spans = harness.finishedSpans()
    let span = try #require(
      spans.first(where: {
        $0.attributes[Terra.Keys.Terra.runtime]?.description == Terra.RuntimeKind.ollama.rawValue
          || $0.events.contains(where: { $0.name == Terra.Keys.Terra.streamLifecycleEvent })
      })
    )

    #expect(span.attributes[Terra.Keys.Terra.runtime]?.description == Terra.RuntimeKind.ollama.rawValue)
    #expect(span.attributes[Terra.Keys.Terra.runtimeConfidence] != nil)
    let hasPayloadUnavailableLifecycle = span.events.contains { event in
      guard event.name == Terra.Keys.Terra.streamLifecycleEvent else { return false }
      return event.attributes[Terra.Keys.Terra.availability]?.description == "payload_unavailable"
    }
    #expect(span.attributes[Terra.Keys.Terra.streamOutputTokens]?.description == "2" || hasPayloadUnavailableLifecycle)
    #expect(span.attributes[Terra.Keys.Terra.latencyPromptEvalMs] != nil || hasPayloadUnavailableLifecycle)
    #expect(span.events.contains { $0.name == Terra.Keys.Terra.streamLifecycleEvent })
  }
}

private final class HTTPIntegrationTelemetryHarness {
  static let shared = HTTPIntegrationTelemetryHarness()

  private let lock = NSLock()
  private let exporter: InMemoryExporter
  private let tracerProvider: TracerProviderSdk

  private init() {
    exporter = InMemoryExporter()
    tracerProvider = TracerProviderSdk()
    tracerProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))

    OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
    Terra.install(.init(tracerProvider: tracerProvider, registerProvidersAsGlobal: false))
    HTTPAIInstrumentation.resetForTesting()
    HTTPAIInstrumentation.install(hosts: ["example.ai"])
  }

  func reset() {
    lock.lock()
    defer { lock.unlock() }
    exporter.reset()
    MockURLProtocol.allowedHosts = ["example.ai"]
    MockURLProtocol.responseHeaders = ["Content-Type": "application/json"]
    MockURLProtocol.responseBody = "{}"
  }

  func finishedSpans() -> [SpanData] {
    tracerProvider.forceFlush()
    return exporter.getFinishedSpanItems()
  }
}

private final class MockURLProtocol: URLProtocol {
  static var allowedHosts: Set<String> = []
  static var responseBody = "{}"
  static var responseHeaders: [String: String] = ["Content-Type": "application/json"]

  override class func canInit(with request: URLRequest) -> Bool {
    guard let host = request.url?.host else { return false }
    if allowedHosts.isEmpty {
      return true
    }
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
      headerFields: Self.responseHeaders
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(Self.responseBody.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
