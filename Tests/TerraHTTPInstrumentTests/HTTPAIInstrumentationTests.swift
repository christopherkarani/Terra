import Testing
import Foundation
@testable import TerraHTTPInstrument
@testable import TerraCore

@Suite("HTTPAIInstrumentation Host Matching")
struct HTTPAIInstrumentationTests {
  @Test("Host boundary match allows exact host and subdomains")
  func hostBoundaryAllowsExactAndSubdomain() {
    #expect(HTTPAIInstrumentation.isHostBoundaryMatch(host: "api.openai.com", target: "api.openai.com"))
    #expect(HTTPAIInstrumentation.isHostBoundaryMatch(host: "foo.api.openai.com", target: "api.openai.com"))
  }

  @Test("Host boundary match rejects suffix confusion")
  func hostBoundaryRejectsSuffixConfusion() {
    #expect(!HTTPAIInstrumentation.isHostBoundaryMatch(host: "evilapi.openai.com", target: "api.openai.com"))
    #expect(!HTTPAIInstrumentation.isHostBoundaryMatch(host: "evil-ai.com", target: "ai.com"))
  }

  @Test("Host boundary match is case-insensitive")
  func hostBoundaryIsCaseInsensitive() {
    #expect(HTTPAIInstrumentation.isHostBoundaryMatch(host: "API.OPENAI.COM", target: "api.openai.com"))
  }

  @Test("Runtime resolver classifies Ollama from local port and path with high confidence")
  func runtimeResolverClassifiesOllama() {
    var request = URLRequest(url: URL(string: "http://localhost:11434/api/chat")!)
    request.httpMethod = "POST"

    let resolution = HTTPAIInstrumentation.resolveRuntimeForTesting(
      request: request,
      parsedRequest: ParsedRequest(model: "qwen2", maxTokens: nil, temperature: nil, stream: true)
    )

    #expect(resolution.runtime == Terra.RuntimeKind.ollama)
    #expect(resolution.confidence >= 0.8)
  }

  @Test("Runtime resolver classifies LM Studio from SSE payload signatures")
  func runtimeResolverClassifiesLMStudioFromResponsePayload() throws {
    let sse = [
      "event: model_load.started",
      #"data: {"event":"model_load.started","model":"llama"}"#,
      "event: chat.response",
      #"data: {"event":"chat.response","model":"llama","choices":[{"delta":{"content":"hi"}}]}"#,
    ].joined(separator: "\n")

    var request = URLRequest(url: URL(string: "http://127.0.0.1:1234/v1/chat/completions")!)
    request.httpMethod = "POST"
    let resolution = HTTPAIInstrumentation.resolveRuntimeForTesting(
      request: request,
      parsedRequest: ParsedRequest(model: "llama", maxTokens: nil, temperature: nil, stream: true),
      responseData: try #require(sse.data(using: .utf8)),
      responseHeaderFields: ["Content-Type": "text/event-stream"]
    )

    #expect(resolution.runtime == Terra.RuntimeKind.lmStudio)
    #expect(resolution.confidence >= 0.8)
  }

  @Test("Runtime resolver falls back to http_api when local signals are ambiguous")
  func runtimeResolverFallsBackOnAmbiguousLocalSignals() {
    var request = URLRequest(url: URL(string: "http://localhost:8080/inference")!)
    request.httpMethod = "POST"
    let resolution = HTTPAIInstrumentation.resolveRuntimeForTesting(
      request: request,
      parsedRequest: ParsedRequest(model: "generic-model", maxTokens: nil, temperature: nil, stream: nil)
    )

    #expect(resolution.runtime == Terra.RuntimeKind.httpAPI)
    #expect(resolution.confidence <= 0.6)
  }
}
