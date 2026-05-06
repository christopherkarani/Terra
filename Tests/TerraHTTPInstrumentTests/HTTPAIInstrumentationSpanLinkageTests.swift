import Foundation
import InMemoryExporter
import OpenTelemetryApi
import OpenTelemetrySdk
import Testing
@testable import TerraCore
@testable import TerraHTTPInstrument

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
private final class HTTPTestContextManager: ContextManager {
  private struct TaskLocalContext: @unchecked Sendable {
    var values: [String: AnyObject] = [:]
  }

  @TaskLocal private static var context = TaskLocalContext()

  func getCurrentContextValue(forKey key: OpenTelemetryContextKeys) -> AnyObject? {
    Self.context.values[key.rawValue]
  }

  func setCurrentContextValue(forKey: OpenTelemetryContextKeys, value: AnyObject) {}
  func removeContextValue(forKey: OpenTelemetryContextKeys, value: AnyObject) {}

  func withCurrentContextValue<T>(
    forKey key: OpenTelemetryContextKeys,
    value: AnyObject?,
    _ operation: () throws -> T
  ) rethrows -> T {
    var context = Self.context
    context.values[key.rawValue] = value
    return try Self.$context.withValue(context, operation: operation)
  }

  func withCurrentContextValue<T>(
    forKey key: OpenTelemetryContextKeys,
    value: AnyObject?,
    _ operation: () async throws -> T
  ) async rethrows -> T {
    var context = Self.context
    context.values[key.rawValue] = value
    return try await Self.$context.withValue(context, operation: operation)
  }
}

private final class HTTPInstrumentationTestSupport {
  private let previousTracerProvider: any TracerProvider
  let tracerProvider: TracerProviderSdk
  let spanExporter: InMemoryExporter

  init() {
    Terra.lockTestingIsolation()
    previousTracerProvider = OpenTelemetry.instance.tracerProvider
    if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
      OpenTelemetry.registerContextManager(contextManager: HTTPTestContextManager())
    }

    spanExporter = InMemoryExporter()
    tracerProvider = TracerProviderSdk()
    tracerProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: spanExporter))
    OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
  }

  deinit {
    OpenTelemetry.registerTracerProvider(tracerProvider: previousTracerProvider)
    Terra.unlockTestingIsolation()
  }

  func finishedSpans() -> [SpanData] {
    tracerProvider.forceFlush()
    return spanExporter.getFinishedSpanItems()
  }
}

@Suite("HTTPAIInstrumentation span linkage", .serialized)
struct HTTPAIInstrumentationSpanLinkageTests {
  private struct SecretTransportError: Error, CustomStringConvertible {
    let secret: String

    var description: String {
      "transport failed with \(secret)"
    }
  }

  @Test("HTTP spans created inside Terra.workflow are children of the workflow span")
  func httpSpanUsesActiveTerraParent() async throws {
    let support = HTTPInstrumentationTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let requestBody = #"{"model":"gpt-4o","messages":[{"role":"user","content":"plan"}],"stream":true}"#
    let requestData = try #require(requestBody.data(using: .utf8))
    let config = HTTPAIInstrumentation.makeConfiguration(
      hosts: HTTPAIInstrumentation.defaultAIHosts,
      openClawGatewayHosts: [],
      openClawMode: "disabled"
    )

    try await Terra.workflow(name: "planner") { _ in
      var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
      request.httpMethod = "POST"
      request.httpBody = requestData

      let tracer = support.tracerProvider.get(instrumentationName: "http-test")
      let builder = tracer.spanBuilder(spanName: "chat api.openai.com").setSpanKind(spanKind: .client)
      config.spanCustomization?(request, builder)
      let span = builder.startSpan()
      span.end()
      return ()
    }

    let spans = support.finishedSpans()
    let root = try #require(spans.first(where: { $0.name == "planner" }))
    let http = try #require(spans.first(where: { $0.name == "chat api.openai.com" }))

    #expect(http.parentSpanId?.hexString == root.spanId.hexString)
    #expect(http.traceId.hexString == root.traceId.hexString)
    #expect(http.attributes[Terra.Keys.GenAI.operationName]?.description == "chat")
    #expect(http.attributes[Terra.Keys.GenAI.promptMessageCount]?.description == "1")
    #expect(http.attributes[Terra.Keys.GenAI.promptRole0]?.description == "user")
  }

  @Test("HTTP prompt capture under capturing privacy emits redacted prompt attributes only")
  func httpPromptCaptureUsesTerraRedaction() async throws {
    let support = HTTPInstrumentationTestSupport()
    Terra.install(
      .init(
        privacy: .init(contentPolicy: .always, redaction: .hashHMACSHA256),
        tracerProvider: support.tracerProvider,
        registerProvidersAsGlobal: false
      )
    )

    let secret = "http-secret-prompt-741"
    let requestBody = """
      {"model":"gpt-4o","messages":[{"role":"user","content":"\(secret)"}]}
      """
    let requestData = try #require(requestBody.data(using: .utf8))
    let config = HTTPAIInstrumentation.makeConfiguration(
      hosts: HTTPAIInstrumentation.defaultAIHosts,
      openClawGatewayHosts: [],
      openClawMode: "disabled"
    )

    var request = URLRequest(
      url: URL(string: "https://api.openai.com/v1/chat/completions")!
    )
    request.httpMethod = "POST"
    request.httpBody = requestData

    let tracer = support.tracerProvider.get(instrumentationName: "http-test")
    let builder = tracer
      .spanBuilder(spanName: "chat api.openai.com")
      .setSpanKind(spanKind: .client)
    config.spanCustomization?(request, builder)
    let span = builder.startSpan()
    span.end()

    let http = try #require(
      support.finishedSpans().first(where: { $0.name == "chat api.openai.com" })
    )
    #expect(http.attributes[Terra.Keys.GenAI.promptContent] == nil)
    #expect(
      http.attributes[Terra.Keys.Terra.promptLength]?.description == "\(secret.count)"
    )
    #expect(http.attributes[Terra.Keys.Terra.promptHMACSHA256] != nil)
    #expect(http.attributes.values.allSatisfy { !$0.description.contains(secret) })
  }

  @Test("Streaming HTTP errors finalize metrics and omit raw error message")
  func streamingErrorFinalizesMetricsAndSanitizesError() async throws {
    let support = HTTPInstrumentationTestSupport()
    Terra.install(
      .init(
        privacy: .init(contentPolicy: .always, redaction: .hashHMACSHA256),
        tracerProvider: support.tracerProvider,
        registerProvidersAsGlobal: false
      )
    )
    HTTPAIInstrumentation.resetForTesting()
    defer { HTTPAIInstrumentation.resetForTesting() }

    let secret = "stream-error-secret-329"
    let expectedErrorType = String(reflecting: SecretTransportError.self)
    let requestBody = """
      {"model":"gpt-4o","messages":[{"role":"user","content":"stream"}],"stream":true}
      """
    let requestData = try #require(requestBody.data(using: .utf8))
    let config = HTTPAIInstrumentation.makeConfiguration(
      hosts: HTTPAIInstrumentation.defaultAIHosts,
      openClawGatewayHosts: [],
      openClawMode: "disabled"
    )

    var request = URLRequest(
      url: URL(string: "https://api.openai.com/v1/chat/completions")!
    )
    request.httpMethod = "POST"
    request.httpBody = requestData

    let tracer = support.tracerProvider.get(instrumentationName: "http-test")
    let builder = tracer
      .spanBuilder(spanName: "chat api.openai.com")
      .setSpanKind(spanKind: .client)
    config.spanCustomization?(request, builder)
    let span = builder.startSpan()

    var instrumentedRequest = request
    config.injectCustomHeaders?(&instrumentedRequest, span)
    config.createdRequest?(instrumentedRequest, span)

    let chunk = #"data: {"usage":{"completion_tokens":7}}"#
    HTTPAIStreamingObserver.shared.recordChunk(
      for: instrumentedRequest,
      data: Data(chunk.utf8)
    )
    config.receivedError?(SecretTransportError(secret: secret), nil, 599, span)
    span.end()

    let http = try #require(
      support.finishedSpans().first(where: { $0.name == "chat api.openai.com" })
    )
    #expect(http.status.isError)
    #expect(http.attributes[Terra.Keys.Terra.streamChunkCount]?.description == "1")
    #expect(http.attributes[Terra.Keys.GenAI.usageOutputTokens]?.description == "7")
    #expect(http.attributes[Terra.Keys.Terra.streamOutputTokens]?.description == "7")
    #expect(http.attributes[Terra.Keys.Terra.streamTimeToFirstTokenMs] != nil)
    #expect(http.attributes["terra.stream.completed"]?.description == "false")
    #expect(http.attributes["error.type"]?.description == expectedErrorType)
    #expect(http.attributes.values.allSatisfy { !$0.description.contains(secret) })
    #expect(!String(describing: http.status).contains(secret))

    let streamError = try #require(
      http.events.first(where: { $0.name == "stream.error" })
    )
    #expect(streamError.attributes["error.type"]?.description == expectedErrorType)
    #expect(streamError.attributes["error.message"] == nil)
    #expect(streamError.attributes.values.allSatisfy { !$0.description.contains(secret) })
  }
}
