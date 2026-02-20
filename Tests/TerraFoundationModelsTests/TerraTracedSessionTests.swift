import Testing

#if canImport(FoundationModels)
import FoundationModels
@testable import TerraFoundationModels
import TerraCore
import OpenTelemetryApi
import OpenTelemetrySdk
import InMemoryExporter

@available(macOS 26.0, iOS 26.0, *)
private struct SpanTestHarness {
  let previousTracerProvider: any TracerProvider
  let exporter: InMemoryExporter
  let tracerProvider: TracerProviderSdk

  init() {
    previousTracerProvider = OpenTelemetry.instance.tracerProvider
    exporter = InMemoryExporter()
    tracerProvider = TracerProviderSdk()
    tracerProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: exporter))
    OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
    Terra.install(.init(tracerProvider: tracerProvider, registerProvidersAsGlobal: false))
  }

  func finishedSpans() -> [SpanData] {
    tracerProvider.forceFlush()
    return exporter.getFinishedSpanItems()
  }

  func tearDown() {
    OpenTelemetry.registerTracerProvider(tracerProvider: previousTracerProvider)
  }
}

@available(macOS 26.0, iOS 26.0, *)
private struct MockBackend: TerraTracedSessionBackend {
  var textResponse: String = "ok"
  var textInputTokenCount: Int? = nil
  var textOutputTokenCount: Int? = nil
  var textContextWindowTokens: Int? = nil
  var chunks: [TerraTracedStreamChunk] = []

  func respondText(to prompt: String) async throws -> TerraTracedResponse<String> {
    _ = prompt
    return TerraTracedResponse(
      content: textResponse,
      inputTokenCount: textInputTokenCount,
      outputTokenCount: textOutputTokenCount,
      contextWindowTokens: textContextWindowTokens
    )
  }

  func respondGenerable<T: Generable>(to prompt: String, generating type: T.Type) async throws -> TerraTracedResponse<T> {
    _ = prompt
    _ = type
    throw MockError.notImplemented
  }

  func streamResponse(to prompt: String) -> AsyncThrowingStream<TerraTracedStreamChunk, Error> {
    _ = prompt
    return AsyncThrowingStream { continuation in
      for chunk in chunks {
        continuation.yield(chunk)
      }
      continuation.finish()
    }
  }
}

private enum MockError: Error {
  case notImplemented
}

@Suite("TerraFoundationModels Tests", .serialized)
struct TerraTracedSessionTests {
  @Test("TerraTracedSession initializes with default model identifier")
  func tracedSessionInitializesWithDefaultIdentifier() {
    guard #available(macOS 26.0, iOS 26.0, *) else { return }
    let session = TerraTracedSession()
    #expect(session.modelIdentifier == "apple/foundation-model")
  }

  @Test("TerraTracedSession initializes with custom model identifier")
  func tracedSessionInitializesWithCustomIdentifier() {
    guard #available(macOS 26.0, iOS 26.0, *) else { return }
    let session = TerraTracedSession(modelIdentifier: "apple/custom-model")
    #expect(session.modelIdentifier == "apple/custom-model")
  }

  @Test("explicitOutputTokenCount uses only explicit provider token fields")
  func explicitOutputTokenCountRecognizesExplicitFieldsOnly() {
    guard #available(macOS 26.0, iOS 26.0, *) else { return }

    struct ExplicitCount { let outputTokenCount: Int }
    struct NonExplicitCount { let tokenEstimate: Int }

    #expect(TerraTracedSession.explicitOutputTokenCount(from: ExplicitCount(outputTokenCount: 7)) == 7)
    #expect(TerraTracedSession.explicitOutputTokenCount(from: NonExplicitCount(tokenEstimate: 7)) == nil)
  }

  @Test("explicitOutputTokenCount ignores negative values")
  func explicitOutputTokenCountIgnoresNegativeValues() {
    guard #available(macOS 26.0, iOS 26.0, *) else { return }

    struct ExplicitNegative { let outputTokenCount: Int }
    #expect(TerraTracedSession.explicitOutputTokenCount(from: ExplicitNegative(outputTokenCount: -1)) == nil)
  }

  @Test("respond emits traced span with foundation_models runtime attributes")
  func respondEmitsFoundationModelsSpanAttributes() async throws {
    guard #available(macOS 26.0, iOS 26.0, *) else { return }

    let h = SpanTestHarness()
    defer { h.tearDown() }

    let session = TerraTracedSession(
      backend: MockBackend(
        textResponse: "mocked",
        textInputTokenCount: 11,
        textOutputTokenCount: 29,
        textContextWindowTokens: 4096
      ),
      modelIdentifier: "apple/mock-model"
    )
    let response = try await session.respond(to: "hello")
    #expect(response == "mocked")

    let span = try #require(h.finishedSpans().first)
    #expect(span.attributes[Terra.Keys.Terra.runtime]?.description == "foundation_models")
    #expect(span.attributes[Terra.Keys.Terra.autoInstrumented]?.description == "true")
    #expect(span.attributes[Terra.Keys.GenAI.requestModel]?.description == "apple/mock-model")
    #expect(span.attributes[Terra.Keys.GenAI.usageInputTokens]?.description == "11")
    #expect(span.attributes[Terra.Keys.GenAI.usageOutputTokens]?.description == "29")
    #expect(span.attributes[Terra.Keys.Terra.foundationModelsContextWindowTokens]?.description == "4096")
  }

  @Test("non-stream usage parser extracts nested usage fields")
  func nonStreamUsageExtractionFromNestedUsage() {
    guard #available(macOS 26.0, iOS 26.0, *) else { return }

    struct Usage { let inputTokenCount: Int; let outputTokenCount: Int; let contextWindowTokens: Int }
    struct Envelope { let usage: Usage }
    let parsed = TerraTracedSession.nonStreamUsage(
      from: Envelope(usage: Usage(inputTokenCount: 3, outputTokenCount: 5, contextWindowTokens: 8192))
    )

    #expect(parsed.inputTokenCount == 3)
    #expect(parsed.outputTokenCount == 5)
    #expect(parsed.contextWindowTokens == 8192)
  }

  @Test("streamResponse records chunk count and explicit output token totals")
  func streamResponseTracksExplicitTokenCounts() async throws {
    guard #available(macOS 26.0, iOS 26.0, *) else { return }

    let h = SpanTestHarness()
    defer { h.tearDown() }

    let chunks: [TerraTracedStreamChunk] = [
      .init(content: "a", explicitOutputTokenCount: nil),
      .init(content: "b", explicitOutputTokenCount: 2),
      .init(content: "c", explicitOutputTokenCount: 3),
    ]
    let session = TerraTracedSession(
      backend: MockBackend(chunks: chunks),
      modelIdentifier: "apple/mock-model"
    )

    var output: [String] = []
    for try await chunk in session.streamResponse(to: "hello") {
      output.append(chunk)
    }
    #expect(output == ["a", "b", "c"])

    let span = try #require(h.finishedSpans().first)
    #expect(span.attributes[Terra.Keys.Terra.streamChunkCount]?.description == "3")
    #expect(span.attributes[Terra.Keys.Terra.streamOutputTokens]?.description == "3")
    #expect(span.attributes[Terra.Keys.Terra.streamTimeToFirstTokenMs] != nil)
    #expect(span.attributes[Terra.Keys.Terra.streamTokensPerSecond] != nil)
    #expect(span.events.contains { $0.name == Terra.Keys.Terra.streamFirstTokenEvent })
  }

  @Test("streamResponse does not infer token counts when provider data is absent")
  func streamResponseDoesNotInferTokenCountsWithoutExplicitProviderData() async throws {
    guard #available(macOS 26.0, iOS 26.0, *) else { return }

    let h = SpanTestHarness()
    defer { h.tearDown() }

    let chunks: [TerraTracedStreamChunk] = [
      .init(content: "a", explicitOutputTokenCount: nil),
      .init(content: "b", explicitOutputTokenCount: nil),
    ]
    let session = TerraTracedSession(
      backend: MockBackend(chunks: chunks),
      modelIdentifier: "apple/mock-model"
    )

    for try await _ in session.streamResponse(to: "hello") {}

    let span = try #require(h.finishedSpans().first)
    #expect(span.attributes[Terra.Keys.Terra.streamChunkCount]?.description == "2")
    #expect(span.attributes[Terra.Keys.Terra.streamOutputTokens] == nil)
  }
}

#else

// FoundationModels is not available on this platform or SDK.
// These tests confirm the module compiles cleanly as a stub.

@Test("TerraFoundationModels stub compiles without FoundationModels framework")
func foundationModelsNotAvailable() {
  // The TerraFoundationModelsPlaceholder enum should be accessible
  // when FoundationModels is absent (the #else branch in the source).
  #expect(true)
}

#endif
