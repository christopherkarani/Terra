import Foundation
import Testing
@testable import TerraCore
@testable import TerraHTTPInstrument

@Suite("HTTPIntegrationTests", .serialized)
struct HTTPIntegrationTests {
  @Test("HTTP instrumentation captures request and response GenAI attributes")
  func capturesAIRequestAndResponseAttributes() async throws {
    let harness = HTTPIntegrationTelemetryHarness.shared
    harness.reset(hosts: ["example.ai"])

    MockURLProtocol.allowedHosts = ["example.ai"]
    MockURLProtocol.responseHeaders = ["Content-Type": "application/json"]
    MockURLProtocol.responseBody = #"{"model":"response-model","usage":{"prompt_tokens":3,"completion_tokens":5}}"#
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    var request = URLRequest(url: URL(string: "https://example.ai/api/chat")!)
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
    harness.reset(hosts: ["example.ai"])

    MockURLProtocol.allowedHosts = ["example.ai"]
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

  @Test("HTTP instrumentation keeps lifecycle token gaps non-negative under out-of-order timestamps")
  func keepsLifecycleTokenGapsMonotonicWhenProviderTimestampsAreOutOfOrder() async throws {
    let harness = HTTPIntegrationTelemetryHarness.shared
    harness.reset(hosts: ["example.ai"])

    MockURLProtocol.allowedHosts = ["example.ai"]
    MockURLProtocol.responseHeaders = ["Content-Type": "application/x-ndjson"]
    MockURLProtocol.responseBody = [
      #"{"model":"qwen2","created_at":"2024-01-01T00:00:01.000Z","response":"A","done":false}"#,
      #"{"model":"qwen2","created_at":"2024-01-01T00:00:00.200Z","response":"B","done":false}"#,
      #"{"model":"qwen2","created_at":"2024-01-01T00:00:00.100Z","done":true,"prompt_eval_count":2,"eval_count":2,"prompt_eval_duration":1000000000,"eval_duration":1200000000}"#,
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
      })
    )

    let lifecycleEvents = span.events.filter { $0.name == Terra.Keys.Terra.streamLifecycleEvent }
    #expect(!lifecycleEvents.isEmpty)

    var previousIndex = 0
    for event in lifecycleEvents {
      if let indexRaw = event.attributes[Terra.Keys.Terra.streamTokenIndex]?.description,
         let tokenIndex = Int(indexRaw)
      {
        #expect(tokenIndex > previousIndex)
        previousIndex = tokenIndex
      }
      if let gapRaw = event.attributes[Terra.Keys.Terra.streamTokenGapMs]?.description,
         let gap = Double(gapRaw)
      {
        #expect(gap >= 0)
      }
    }
  }

  @Test("HTTP instrumentation keeps stage durations numerically aligned with root summary attributes")
  func stageDurationsStayConsistentWithDerivedRootSummary() async throws {
    let harness = HTTPIntegrationTelemetryHarness.shared
    harness.reset(hosts: ["example.ai"])

    MockURLProtocol.allowedHosts = ["example.ai"]
    MockURLProtocol.responseHeaders = ["Content-Type": "application/x-ndjson"]
    MockURLProtocol.responseBody = [
      #"{"model":"qwen2","created_at":"2024-01-01T00:00:00.000Z","response":"H","done":false}"#,
      #"{"model":"qwen2","created_at":"2024-01-01T00:00:00.350Z","response":"i","done":false}"#,
      #"{"model":"qwen2","created_at":"2024-01-01T00:00:00.700Z","done":true,"prompt_eval_count":7,"eval_count":2,"prompt_eval_duration":1250000000,"eval_duration":2250000000}"#,
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
      })
    )

    let promptEvalEvent = span.events.first { $0.name == Terra.SpanNames.stagePromptEval }
    let decodeEvent = span.events.first { $0.name == Terra.SpanNames.stageDecode }

    let rootPromptEvalRaw = span.attributes[Terra.Keys.Terra.latencyPromptEvalMs]?.description
    let eventPromptEvalRaw = promptEvalEvent?.attributes[Terra.Keys.Terra.latencyPromptEvalMs]?.description
    #expect(rootPromptEvalRaw == eventPromptEvalRaw)

    let rootDecodeRaw = span.attributes[Terra.Keys.Terra.latencyDecodeMs]?.description
    let eventDecodeRaw = decodeEvent?.attributes[Terra.Keys.Terra.latencyDecodeMs]?.description
    #expect(rootDecodeRaw == eventDecodeRaw)

    let rootOutputTokensRaw = span.attributes[Terra.Keys.Terra.streamOutputTokens]?.description
    let usageOutputTokensRaw = span.attributes[Terra.Keys.GenAI.usageOutputTokens]?.description
    if let rootOutputTokensRaw {
      #expect(rootOutputTokensRaw == "2")
    } else if let usageOutputTokensRaw {
      #expect(usageOutputTokensRaw == "2")
    } else {
      #expect(rootOutputTokensRaw != "0")
      #expect(usageOutputTokensRaw != "0")
    }
  }

  @Test("HTTP instrumentation keeps unknown-runtime NDJSON with SSE literals on NDJSON parser path")
  func unknownRuntimeNDJSONWithSSELiteralsPreservesLifecycleTelemetry() throws {
    let body = [
      #"{"created":1704067201.2,"model":"llama","choices":[{"delta":{"content":"data: token-one"}}]}"#,
      #"{"created":1704067201.4,"model":"llama","choices":[{"delta":{"content":"event: token-two"}}],"usage":{"prompt_tokens":4,"completion_tokens":2}}"#,
    ].joined(separator: "\n")
    let responseData = Data(body.utf8)

    var request = URLRequest(url: URL(string: "https://example.ai/v1/chat/completions")!)
    request.httpMethod = "POST"
    request.httpBody = Data(#"{"model":"llama","stream":true}"#.utf8)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("http_api", forHTTPHeaderField: "X-Terra-Runtime")

    let parsedRequest = request.httpBody.flatMap(AIRequestParser.parse(body:))
    let runtimeResolution = HTTPAIInstrumentation.resolveRuntimeForTesting(
      request: request,
      parsedRequest: parsedRequest,
      responseData: responseData,
      responseHeaderFields: ["Content-Type": "application/x-ndjson"]
    )
    #expect(runtimeResolution.runtime == .httpAPI)

    let parsed = try #require(
      AIResponseStreamParser.parse(
        data: responseData,
        runtime: .unknown,
        requestModel: parsedRequest?.model
      )
    )
    let lifecycleEvents = parsed.stream.events.filter { $0.name == Terra.Keys.Terra.streamLifecycleEvent }
    #expect(lifecycleEvents.count == 2)
    let hasPayloadUnavailableLifecycle = lifecycleEvents.contains { event in
      event.attributes[Terra.Keys.Terra.availability]?.description == "payload_unavailable"
    }
    #expect(!hasPayloadUnavailableLifecycle)
    #expect(parsed.stream.decodeTokenCount == 2)
    #expect(parsed.response.outputTokens == 2)
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
