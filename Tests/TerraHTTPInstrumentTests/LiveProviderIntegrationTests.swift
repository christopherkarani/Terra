import Foundation
import XCTest
@testable import TerraCore
@testable import TerraHTTPInstrument

final class LiveProviderIntegrationTests: XCTestCase {
  private enum LiveCaseKind {
    case ollamaNative(streaming: Bool)
    case ollamaOpenAICompatible(streaming: Bool)
    case lmStudioNativeSSE
    case lmStudioOpenAICompatible(streaming: Bool)

    var expectedRuntime: Terra.RuntimeKind {
      switch self {
      case .ollamaNative, .ollamaOpenAICompatible:
        return .ollama
      case .lmStudioNativeSSE, .lmStudioOpenAICompatible:
        return .lmStudio
      }
    }

    var isStreaming: Bool {
      switch self {
      case .ollamaNative(let streaming), .ollamaOpenAICompatible(let streaming), .lmStudioOpenAICompatible(let streaming):
        return streaming
      case .lmStudioNativeSSE:
        return true
      }
    }

    var id: String {
      switch self {
      case .ollamaNative(let streaming):
        return streaming ? "ollama-native-stream" : "ollama-native-non-stream"
      case .ollamaOpenAICompatible(let streaming):
        return streaming ? "ollama-openai-stream" : "ollama-openai-non-stream"
      case .lmStudioNativeSSE:
        return "lmstudio-native-sse-stream"
      case .lmStudioOpenAICompatible(let streaming):
        return streaming ? "lmstudio-openai-stream" : "lmstudio-openai-non-stream"
      }
    }
  }

  private struct LiveResponse {
    let statusCode: Int
    let contentType: String
    let body: Data
    let usedStreamingAPI: Bool
  }

  private let requiredRootAttributes: Set<String> = [
    Terra.Keys.Terra.semanticVersion,
    Terra.Keys.Terra.schemaFamily,
    Terra.Keys.Terra.runtime,
    Terra.Keys.Terra.requestID,
    Terra.Keys.Terra.sessionID,
    Terra.Keys.Terra.modelFingerprint,
  ]

  private lazy var ollamaBaseURL = URL(string: environment("TERRA_LIVE_OLLAMA_BASE_URL", default: "http://127.0.0.1:11434"))
  private lazy var lmStudioBaseURL = URL(string: environment("TERRA_LIVE_LMSTUDIO_BASE_URL", default: "http://127.0.0.1:1234"))
  private lazy var ollamaModel = environment("TERRA_LIVE_OLLAMA_MODEL", default: "llama3.2:1b")
  private lazy var lmStudioModel = environment("TERRA_LIVE_LMSTUDIO_MODEL", default: "llama-3.2-1b-instruct")

  func testLiveOllamaNDJSONStreamAndNonStream() async throws {
    try requireLiveTestsEnabled()
    guard let baseURL = ollamaBaseURL else {
      throw XCTSkip("Skipping live Ollama tests: invalid TERRA_LIVE_OLLAMA_BASE_URL")
    }
    try await requireEndpointReachable(baseURL, label: "ollama")

    try await executeCase(.ollamaNative(streaming: true), baseURL: baseURL)
    try await executeCase(.ollamaNative(streaming: false), baseURL: baseURL)
  }

  func testLiveOllamaOpenAICompatibleStreamAndNonStream() async throws {
    try requireLiveTestsEnabled()
    guard let baseURL = ollamaBaseURL else {
      throw XCTSkip("Skipping live Ollama compatibility tests: invalid TERRA_LIVE_OLLAMA_BASE_URL")
    }
    try await requireEndpointReachable(baseURL, label: "ollama")

    try await executeCase(.ollamaOpenAICompatible(streaming: true), baseURL: baseURL)
    try await executeCase(.ollamaOpenAICompatible(streaming: false), baseURL: baseURL)
  }

  func testLiveLMStudioNativeSSEStream() async throws {
    try requireLiveTestsEnabled()
    guard let baseURL = lmStudioBaseURL else {
      throw XCTSkip("Skipping LM Studio native SSE test: invalid TERRA_LIVE_LMSTUDIO_BASE_URL")
    }
    try await requireEndpointReachable(baseURL, label: "lmstudio")

    try await executeCase(.lmStudioNativeSSE, baseURL: baseURL)
  }

  func testLiveLMStudioOpenAICompatibleStreamAndNonStream() async throws {
    try requireLiveTestsEnabled()
    guard let baseURL = lmStudioBaseURL else {
      throw XCTSkip("Skipping LM Studio compatibility tests: invalid TERRA_LIVE_LMSTUDIO_BASE_URL")
    }
    try await requireEndpointReachable(baseURL, label: "lmstudio")

    try await executeCase(.lmStudioOpenAICompatible(streaming: true), baseURL: baseURL)
    try await executeCase(.lmStudioOpenAICompatible(streaming: false), baseURL: baseURL)
  }

  private func executeCase(_ kind: LiveCaseKind, baseURL: URL) async throws {
    let host = baseURL.host ?? ""
    let harness = HTTPIntegrationTelemetryHarness.shared
    harness.reset(hosts: [host])

    let request = try buildRequest(for: kind, baseURL: baseURL)
    let response = try await send(request: request, streaming: kind.isStreaming)
    try validateResponseShape(kind: kind, response: response)

    let spans = harness.finishedSpans()
    guard let span = spans.last(where: { $0.name.contains("chat") || $0.name.contains("inference") }) else {
      XCTFail("Expected telemetry span for live case \(kind.id)")
      return
    }

    XCTAssertEqual(
      span.attributes[Terra.Keys.Terra.runtime]?.description,
      kind.expectedRuntime.rawValue,
      "Live case \(kind.id) did not classify the expected runtime"
    )

    for key in requiredRootAttributes {
      XCTAssertNotNil(span.attributes[key], "Live case \(kind.id) missing required root attribute: \(key)")
    }

    if kind.isStreaming {
      XCTAssertTrue(
        response.usedStreamingAPI,
        "Live case \(kind.id) must use URLSession.bytes(for:) for streaming coverage"
      )

      let hasStreamLifecycle = span.events.contains { $0.name == Terra.Keys.Terra.streamLifecycleEvent }
      XCTAssertTrue(
        hasStreamLifecycle,
        "Live case \(kind.id) expected stream lifecycle events in captured telemetry"
      )
    }

    let bodyText = String(decoding: response.body, as: UTF8.self)
    let containsUsageSignals = bodyText.contains("\"usage\"")
      || bodyText.contains("\"prompt_eval_count\"")
      || bodyText.contains("\"eval_count\"")

    if containsUsageSignals {
      let hasUsageOrTiming =
        span.attributes[Terra.Keys.GenAI.usageInputTokens] != nil
        || span.attributes[Terra.Keys.GenAI.usageOutputTokens] != nil
        || span.attributes[Terra.Keys.Terra.streamOutputTokens] != nil
        || span.attributes[Terra.Keys.Terra.latencyPromptEvalMs] != nil
        || span.attributes[Terra.Keys.Terra.latencyDecodeMs] != nil
      XCTAssertTrue(
        hasUsageOrTiming,
        "Live case \(kind.id) exposed usage/timing payload signals but telemetry did not capture any usage/timing attributes"
      )
    } else {
      XCTAssertFalse(
        span.attributes[Terra.Keys.GenAI.usageOutputTokens]?.description == "0",
        "Live case \(kind.id) should not coerce missing usage to zero"
      )
      XCTAssertFalse(
        span.attributes[Terra.Keys.Terra.streamOutputTokens]?.description == "0",
        "Live case \(kind.id) should not coerce missing stream tokens to zero"
      )
    }
  }

  private func buildRequest(for kind: LiveCaseKind, baseURL: URL) throws -> URLRequest {
    let prompt = "Respond with exactly one word: terra"
    let bodyObject: [String: Any]
    let endpoint: String

    switch kind {
    case .ollamaNative(let streaming):
      endpoint = "api/chat"
      bodyObject = [
        "model": ollamaModel,
        "messages": [["role": "user", "content": prompt]],
        "stream": streaming,
      ]

    case .ollamaOpenAICompatible(let streaming):
      endpoint = "v1/chat/completions"
      var payload: [String: Any] = [
        "model": ollamaModel,
        "messages": [["role": "user", "content": prompt]],
        "stream": streaming,
      ]
      if streaming {
        payload["stream_options"] = ["include_usage": true]
      }
      bodyObject = payload

    case .lmStudioNativeSSE:
      endpoint = "api/v0/chat/completions"
      bodyObject = [
        "model": lmStudioModel,
        "messages": [["role": "user", "content": prompt]],
        "stream": true,
      ]

    case .lmStudioOpenAICompatible(let streaming):
      endpoint = "v1/chat/completions"
      var payload: [String: Any] = [
        "model": lmStudioModel,
        "messages": [["role": "user", "content": prompt]],
        "stream": streaming,
      ]
      if streaming {
        payload["stream_options"] = ["include_usage": true]
      }
      bodyObject = payload
    }

    let requestURL = baseURL.appendingPathComponent(endpoint)
    var request = URLRequest(url: requestURL)
    request.httpMethod = "POST"
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: bodyObject)
    return request
  }

  private func send(request: URLRequest, streaming: Bool) async throws -> LiveResponse {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 20
    let session = URLSession(configuration: config)

    if streaming {
      let (bytes, response) = try await session.bytes(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw XCTSkip("Skipping live case: non-HTTP response")
      }

      var body = Data()
      body.reserveCapacity(128 * 1024)
      for try await line in bytes.lines {
        guard !line.isEmpty else { continue }
        body.append(contentsOf: line.utf8)
        body.append(0x0A)
        if line.contains("[DONE]") || line.contains("\"done\":true") {
          break
        }
        if body.count >= 512 * 1024 {
          break
        }
      }

      return LiveResponse(
        statusCode: httpResponse.statusCode,
        contentType: httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown",
        body: body,
        usedStreamingAPI: true
      )
    }

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw XCTSkip("Skipping live case: non-HTTP response")
    }

    return LiveResponse(
      statusCode: httpResponse.statusCode,
      contentType: httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown",
      body: data,
      usedStreamingAPI: false
    )
  }

  private func validateResponseShape(kind: LiveCaseKind, response: LiveResponse) throws {
    let unsupportedStatusCodes: Set<Int> = [404, 405, 406, 415, 422, 501]
    if unsupportedStatusCodes.contains(response.statusCode) {
      throw XCTSkip(
        "Skipping live case \(kind.id): unsupported endpoint shape (status=\(response.statusCode), content-type=\(response.contentType))"
      )
    }

    let bodyText = String(decoding: response.body.prefix(2048), as: UTF8.self)
    if bodyText.localizedCaseInsensitiveContains("model")
      && bodyText.localizedCaseInsensitiveContains("not found")
    {
      throw XCTSkip("Skipping live case \(kind.id): required model is unavailable on provider")
    }

    guard (200..<300).contains(response.statusCode) else {
      XCTFail(
        "Live case \(kind.id) returned status=\(response.statusCode), content-type=\(response.contentType), body=\(bodyText)"
      )
      return
    }

    if kind.isStreaming {
      let normalizedContentType = response.contentType.lowercased()
      let supportsStreaming = normalizedContentType.contains("text/event-stream")
        || normalizedContentType.contains("application/x-ndjson")
        || normalizedContentType.contains("application/json")
      if !supportsStreaming {
        throw XCTSkip(
          "Skipping live case \(kind.id): unsupported streaming content-type=\(response.contentType)"
        )
      }
      return
    }

    let normalizedContentType = response.contentType.lowercased()
    if !normalizedContentType.contains("application/json") {
      throw XCTSkip(
        "Skipping live case \(kind.id): unsupported non-stream content-type=\(response.contentType)"
      )
    }
  }

  private func requireLiveTestsEnabled() throws {
    let raw = ProcessInfo.processInfo.environment["TERRA_ENABLE_LIVE_PROVIDER_TESTS"] ?? "0"
    if !isTruthy(raw) {
      throw XCTSkip("Skipping live provider tests: set TERRA_ENABLE_LIVE_PROVIDER_TESTS=1 to enable")
    }
  }

  private func requireEndpointReachable(_ baseURL: URL, label: String) async throws {
    var request = URLRequest(url: baseURL)
    request.httpMethod = "GET"
    request.timeoutInterval = 2

    do {
      _ = try await URLSession.shared.data(for: request)
    } catch let error as URLError {
      switch error.code {
      case .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .timedOut:
        throw XCTSkip(
          "Skipping live \(label) cases: endpoint unavailable at \(baseURL.absoluteString) (\(error.code.rawValue))"
        )
      default:
        throw error
      }
    }
  }

  private func environment(_ key: String, default defaultValue: String) -> String {
    let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let value, !value.isEmpty {
      return value
    }
    return defaultValue
  }

  private func isTruthy(_ value: String) -> Bool {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "1", "true", "yes", "on":
      return true
    default:
      return false
    }
  }
}
