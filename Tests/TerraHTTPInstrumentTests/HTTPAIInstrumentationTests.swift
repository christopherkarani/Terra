import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import Testing
@testable import TerraCore
@testable import TerraHTTPInstrument

@Suite("HTTPAIInstrumentation Host Matching", .serialized)
struct HTTPAIInstrumentationTests {
  private final class ConfigurationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var configuration: HTTPAIInstrumentation.Configuration

    init(_ configuration: HTTPAIInstrumentation.Configuration) {
      self.configuration = configuration
    }

    func load() -> HTTPAIInstrumentation.Configuration {
      lock.lock()
      let configuration = self.configuration
      lock.unlock()
      return configuration
    }

    func store(_ configuration: HTTPAIInstrumentation.Configuration) {
      lock.lock()
      self.configuration = configuration
      lock.unlock()
    }
  }

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

  @Test("Configuration closures can observe runtime host updates")
  func configurationClosuresObserveUpdates() {
    let box = ConfigurationBox(.init(
      hosts: ["one.example"],
      openClawGatewayHosts: [],
      openClawMode: "disabled"
    ))
    let config = HTTPAIInstrumentation.makeConfiguration(
      hosts: ["one.example"],
      openClawGatewayHosts: [],
      openClawMode: "disabled",
      configurationProvider: { box.load() }
    )

    let one = URLRequest(url: URL(string: "https://one.example/v1/chat/completions")!)
    let two = URLRequest(url: URL(string: "https://two.example/v1/chat/completions")!)

    #expect(config.shouldInstrument?(one) == true)
    #expect(config.shouldInstrument?(two) == false)

    box.store(.init(
      hosts: ["two.example"],
      openClawGatewayHosts: [],
      openClawMode: "disabled"
    ))

    #expect(config.shouldInstrument?(one) == false)
    #expect(config.shouldInstrument?(two) == true)
    #expect(config.nameSpan?(two) == "chat two.example")
  }

  @Test("Request parsing intentionally ignores httpBodyStream")
  func requestParsingIgnoresBodyStreams() {
    let body = #"{"model":"gpt-4o","messages":[{"role":"user","content":"secret"}]}"#
      .data(using: .utf8)!
    var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
    request.httpBodyStream = InputStream(data: body)

    #expect(HTTPAIInstrumentation.parsedRequestBody(for: request) == nil)
  }

  @Test("Sanitized URL strips query credentials and fragments")
  func sanitizedURLStripsSecrets() throws {
    let url = try #require(URL(string: "https://user:pass@generativelanguage.googleapis.com/v1beta/models/gemini:generateContent?key=secret#frag"))

    #expect(
      HTTPAIInstrumentation.sanitizedURLString(url)
        == "https://generativelanguage.googleapis.com"
    )
  }

  @Test("Sanitized URL strips path secrets by default")
  func sanitizedURLStripsPathSecrets() throws {
    let url = try #require(URL(string: "https://api.example.com/v1/chat/tenant-secret/completions?token=secret"))

    #expect(HTTPAIInstrumentation.sanitizedURLString(url) == "https://api.example.com")
  }

  // P0-4: shouldRecordPayload must be wired so URLSessionInstrumentation buffers
  // response bodies. Without this, gen_ai.usage.* are never populated for
  // session-delegate clients.
  @Test("shouldRecordPayload is wired so URLSessionInstrumentation buffers payloads")
  func shouldRecordPayloadIsWiredForAIHosts() {
    let config = HTTPAIInstrumentation.makeConfiguration(
      hosts: ["api.openai.com"],
      openClawGatewayHosts: [],
      openClawMode: "disabled"
    )

    // Presence of the closure is the primary contract — if nil, payloads
    // are never recorded for session-delegate callers (the original bug).
    #expect(config.shouldRecordPayload != nil)
    #expect(config.shouldRecordPayload?(URLSession.shared) == true)
  }

  @Test("Streaming chunk parser surfaces output tokens from full SSE body")
  func streamingChunkParserHandlesFullSSEBody() throws {
    let body = """
      data: {"choices":[{"delta":{"content":"hello"}}]}\n\n\
      data: {"choices":[{"delta":{"content":" world"}}]}\n\n\
      data: {"usage":{"completion_tokens":17}}\n\n\
      data: [DONE]\n\n
      """
    let data = try #require(body.data(using: .utf8))
    #expect(AIStreamingChunkParser.outputTokens(from: data) == 17)
  }

  @Test("Streaming observer evicts oldest orphan state")
  func streamingObserverEvictsOldestOrphanState() throws {
    let observer = HTTPAIStreamingObserver.shared
    observer.reset()
    defer { observer.reset() }

    let provider = TracerProviderSdk()
    let tracer = provider.get(instrumentationName: "terra-http-test")
    let parsed = ParsedRequest(model: nil, maxTokens: nil, temperature: nil, stream: true, messages: [])
    var firstSpan: (any Span)?

    for index in 0...1_024 {
      let span = tracer.spanBuilder(spanName: "stream-\(index)").startSpan()
      if index == 0 { firstSpan = span }
      var request = URLRequest(url: URL(string: "https://api.example.com/v1/chat/\(index)")!)
      observer.attachProperties(to: &request, span: span, parsedRequest: parsed)
      observer.register(request: request, span: span, parsedRequest: parsed)
    }

    let oldest = try #require(firstSpan)
    #expect(observer.registeredRequest(forSpan: oldest) == nil)
  }
}
