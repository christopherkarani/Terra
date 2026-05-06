import Testing

#if canImport(FoundationModels)
import FoundationModels
@testable import TerraCore
@testable import TerraFoundationModels
import OpenTelemetryApi
import OpenTelemetrySdk
import InMemoryExporter

@available(macOS 26.0, iOS 26.0, *)
private struct SpanHarness {
  let previousTracerProvider: any TracerProvider
  let spanExporter: InMemoryExporter
  let tracerProvider: TracerProviderSdk

  init(privacy: Terra.Privacy = .default) {
    previousTracerProvider = OpenTelemetry.instance.tracerProvider
    Terra.resetOpenTelemetryForTesting()
    spanExporter = InMemoryExporter()
    tracerProvider = TracerProviderSdk()
    tracerProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: spanExporter))
    OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
    Terra.install(.init(privacy: privacy, tracerProvider: tracerProvider, registerProvidersAsGlobal: false))
  }

  func finishedSpans() -> [SpanData] {
    tracerProvider.forceFlush()
    return spanExporter.getFinishedSpanItems()
  }

  func tearDown() {
    Terra.resetOpenTelemetryForTesting()
    OpenTelemetry.registerTracerProvider(tracerProvider: previousTracerProvider)
  }
}

@available(macOS 26.0, iOS 26.0, *)
private final class MockBackend: TerraTracedSessionBackend, @unchecked Sendable {
  struct InvalidMockType: Error {}

  struct ToolCallEntry: Sendable {
    let toolName: String
    let arguments: String
    let toolCall = true
  }

  struct ToolResultEntry: Sendable {
    let toolName: String
    let result: String
    let toolResult = true
  }

  private var beforeTranscript: [Any]
  private var afterTranscript: [Any]
  private var currentTranscript: [Any]
  private let responseText: String
  private let thrownError: (any Error)?
  private let generationAttributes: [String: Terra.TelemetryAttributeValue]

  init(
    beforeTranscript: [Any] = [],
    afterTranscript: [Any] = [],
    responseText: String = "ok",
    thrownError: (any Error)? = nil,
    generationAttributes: [String: Terra.TelemetryAttributeValue] = [:]
  ) {
    self.beforeTranscript = beforeTranscript
    self.afterTranscript = afterTranscript
    currentTranscript = beforeTranscript
    self.responseText = responseText
    self.thrownError = thrownError
    self.generationAttributes = generationAttributes
  }

  func respond(to prompt: String) async throws -> String {
    currentTranscript = afterTranscript
    if let thrownError {
      throw thrownError
    }
    return responseText
  }

  func respond<T>(to prompt: String, generating type: T.Type) async throws -> T where T: Generable {
    currentTranscript = afterTranscript
    if let thrownError {
      throw thrownError
    }
    guard let value = responseText as? T else {
      throw InvalidMockType()
    }
    return value
  }

  func streamResponse(to prompt: String) -> AsyncThrowingStream<TerraTracedSessionStreamChunk, Error> {
    AsyncThrowingStream { continuation in
      continuation.yield(.init(content: responseText, outputTokenCount: 3))
      continuation.finish()
    }
  }

  func transcriptEntries() -> [Any] {
    currentTranscript
  }

  func generationOptionsAttributes() -> [String: Terra.TelemetryAttributeValue] {
    generationAttributes
  }
}

@available(macOS 26.0, iOS 26.0, *)
private enum GuardrailError: Error, CustomStringConvertible {
  case blocked

  var description: String {
    "guardrail blocked response"
  }
}

@Suite("TerraFoundationModels top-level", .serialized)
struct TerraTracedSessionTopLevelTests {
@available(macOS 26.0, iOS 26.0, *)
@Test("TerraTracedSession initializes with default model identifier")
func tracedSessionInitializesWithDefaultIdentifier() {
  Terra.lockTestingIsolation()
  defer { Terra.unlockTestingIsolation() }

  let session = TerraTracedSession()
  let defaultModel = "apple/foundation-model"
  #expect(session.modelIdentifier == defaultModel)
}

@available(macOS 26.0, iOS 26.0, *)
@Test("TerraTracedSession initializes with custom model identifier")
func tracedSessionInitializesWithCustomIdentifier() {
  Terra.lockTestingIsolation()
  defer { Terra.unlockTestingIsolation() }

  let modelID = "apple/custom-model"
  let session = TerraTracedSession(modelIdentifier: modelID)
  #expect(session.modelIdentifier == modelID)
}

@available(macOS 26.0, iOS 26.0, *)
@Test("Transcript diff emits tool call/result events and metadata")
func transcriptDiffEmitsToolEvents() async throws {
  Terra.lockTestingIsolation()
  defer { Terra.unlockTestingIsolation() }

  // Length-only redaction with content captured opt-in: preserves the legacy
  // `[redacted: N chars]` payload that this test asserts on.
  let harness = SpanHarness(
    privacy: .init(contentPolicy: .always, redaction: .lengthOnly)
  )
  defer { harness.tearDown() }

  let backend = MockBackend(
    afterTranscript: [
      MockBackend.ToolCallEntry(toolName: "search", arguments: "{\"q\":\"swift\"}"),
      MockBackend.ToolResultEntry(toolName: "search", result: "{\"hits\":1}"),
    ]
  )
  let session = TerraTracedSession(backend: backend)
  _ = try await session.respond(to: "Find swift docs [transcript-diff]", promptCapture: .includeContent)

  let span = try #require(
    harness.finishedSpans().last(where: {
      $0.name == "gen_ai.inference"
        && $0.attributes["terra.fm.tool_call_count"]?.description == "1"
    })
  )
  #expect(span.events.contains { $0.name == "tool_call" })
  #expect(span.events.contains { $0.name == "tool_result" })
  let toolCall = try #require(span.events.first { $0.name == "tool_call" })
  let toolResult = try #require(span.events.first { $0.name == "tool_result" })
  #expect(toolCall.attributes["terra.fm.tool.arguments"]?.description == "[redacted: 13 chars]")
  #expect(toolResult.attributes["terra.fm.tool.result"]?.description == "[redacted: 10 chars]")
  #expect(toolCall.attributes["terra.fm.tool.arguments"]?.description.contains("swift") == false)
  #expect(toolResult.attributes["terra.fm.tool.result"]?.description.contains("hits") == false)
  #expect(span.attributes["terra.fm.tools.called"]?.description == "search")
  #expect(span.attributes["terra.fm.tool_call_count"]?.description == "1")
}

@available(macOS 26.0, iOS 26.0, *)
@Test("Tool content redaction respects hashHMACSHA256 policy")
func testToolContentRedactionRespectsHashHMACPolicy() async throws {
  Terra.lockTestingIsolation()
  defer { Terra.unlockTestingIsolation() }

  let harness = SpanHarness(
    privacy: .init(contentPolicy: .always, redaction: .hashHMACSHA256)
  )
  defer { harness.tearDown() }

  let backend = MockBackend(
    afterTranscript: [
      MockBackend.ToolCallEntry(toolName: "search", arguments: "{\"q\":\"swift\"}"),
      MockBackend.ToolResultEntry(toolName: "search", result: "{\"hits\":1}"),
    ]
  )
  let session = TerraTracedSession(backend: backend)
  _ = try await session.respond(to: "Find swift docs [hmac]", promptCapture: .includeContent)

  let span = try #require(
    harness.finishedSpans().last(where: {
      $0.name == "gen_ai.inference"
        && $0.attributes["terra.fm.tool_call_count"]?.description == "1"
    })
  )

  let toolCall = try #require(span.events.first { $0.name == "tool_call" })
  let toolResult = try #require(span.events.first { $0.name == "tool_result" })

  let argumentsValue = try #require(toolCall.attributes["terra.fm.tool.arguments"]?.description)
  let resultValue = try #require(toolResult.attributes["terra.fm.tool.result"]?.description)

  #expect(argumentsValue.contains("hmac_sha256:"))
  #expect(argumentsValue.contains("len:13"))
  #expect(argumentsValue.contains("swift") == false)
  #expect(argumentsValue.contains("[redacted:") == false)
  #expect(resultValue.contains("hmac_sha256:"))
  #expect(resultValue.contains("len:10"))
  #expect(resultValue.contains("hits") == false)

  // Aggregate counters always emit regardless of redaction.
  #expect(span.attributes["terra.fm.tools.called"]?.description == "search")
  #expect(span.attributes["terra.fm.tool_call_count"]?.description == "1")
}

@available(macOS 26.0, iOS 26.0, *)
@Test("Tool content redaction respects lengthOnly policy")
func testToolContentRedactionRespectsLengthOnlyPolicy() async throws {
  Terra.lockTestingIsolation()
  defer { Terra.unlockTestingIsolation() }

  let harness = SpanHarness(
    privacy: .init(contentPolicy: .always, redaction: .lengthOnly)
  )
  defer { harness.tearDown() }

  let backend = MockBackend(
    afterTranscript: [
      MockBackend.ToolCallEntry(toolName: "search", arguments: "{\"q\":\"swift\"}"),
      MockBackend.ToolResultEntry(toolName: "search", result: "{\"hits\":1}"),
    ]
  )
  let session = TerraTracedSession(backend: backend)
  _ = try await session.respond(to: "Find swift docs [length-only]", promptCapture: .includeContent)

  let span = try #require(
    harness.finishedSpans().last(where: {
      $0.name == "gen_ai.inference"
        && $0.attributes["terra.fm.tool_call_count"]?.description == "1"
    })
  )

  let toolCall = try #require(span.events.first { $0.name == "tool_call" })
  let toolResult = try #require(span.events.first { $0.name == "tool_result" })

  #expect(toolCall.attributes["terra.fm.tool.arguments"]?.description == "[redacted: 13 chars]")
  #expect(toolResult.attributes["terra.fm.tool.result"]?.description == "[redacted: 10 chars]")
  #expect(span.attributes["terra.fm.tool_call_count"]?.description == "1")
}

@available(macOS 26.0, iOS 26.0, *)
@Test("Tool content under drop policy omits content")
func testToolContentRedactionUnderDropPolicyOmitsContent() async throws {
  Terra.lockTestingIsolation()
  defer { Terra.unlockTestingIsolation() }

  let harness = SpanHarness(
    privacy: .init(contentPolicy: .always, redaction: .drop)
  )
  defer { harness.tearDown() }

  let backend = MockBackend(
    afterTranscript: [
      MockBackend.ToolCallEntry(toolName: "search", arguments: "{\"q\":\"swift\"}"),
      MockBackend.ToolResultEntry(toolName: "search", result: "{\"hits\":1}"),
    ]
  )
  let session = TerraTracedSession(backend: backend)
  _ = try await session.respond(to: "Find swift docs [drop]", promptCapture: .includeContent)

  let span = try #require(
    harness.finishedSpans().last(where: {
      $0.name == "gen_ai.inference"
        && $0.attributes["terra.fm.tool_call_count"]?.description == "1"
    })
  )

  let toolCall = try #require(span.events.first { $0.name == "tool_call" })
  let toolResult = try #require(span.events.first { $0.name == "tool_result" })

  // Under .drop, the tool content attribute must be absent entirely (no length, no hash).
  #expect(toolCall.attributes["terra.fm.tool.arguments"] == nil)
  #expect(toolResult.attributes["terra.fm.tool.result"] == nil)

  // Aggregate counters still surface — only content is dropped.
  #expect(span.attributes["terra.fm.tools.called"]?.description == "search")
  #expect(span.attributes["terra.fm.tool_call_count"]?.description == "1")
}

@available(macOS 26.0, iOS 26.0, *)
@Test("Guardrail errors emit safety-check child span")
func guardrailErrorEmitsSafetySpan() async throws {
  Terra.lockTestingIsolation()
  defer { Terra.unlockTestingIsolation() }

  let harness = SpanHarness()
  defer { harness.tearDown() }

  let backend = MockBackend(thrownError: GuardrailError.blocked)
  let session = TerraTracedSession(backend: backend)

  await #expect(throws: GuardrailError.self) {
    _ = try await session.respond(to: "Unsafe request")
  }

  let spans = harness.finishedSpans()
  let safetySpan = try #require(spans.first(where: { $0.name == "terra.safety_check" }))
  #expect(safetySpan.attributes[Terra.Keys.Terra.safetyCheckName]?.description == "foundation-model-guardrail")
}

@available(macOS 26.0, iOS 26.0, *)
@Test("Generation options are captured as inference span attributes")
func generationOptionsCaptured() async throws {
  Terra.lockTestingIsolation()
  defer { Terra.unlockTestingIsolation() }

  let harness = SpanHarness()
  defer { harness.tearDown() }

  let backend = MockBackend(
    generationAttributes: [
      Terra.Keys.GenAI.requestTemperature: .double(0.4),
      Terra.Keys.GenAI.requestMaxTokens: .int(512),
      "terra.fm.generation.sampling_mode": .string("top_p"),
    ]
  )
  let session = TerraTracedSession(backend: backend)
  _ = try await session.respond(to: "Hello")

  let span = try #require(harness.finishedSpans().first(where: { $0.name == "gen_ai.inference" }))
  #expect(span.attributes[Terra.Keys.GenAI.requestTemperature]?.description == "0.4")
  #expect(span.attributes[Terra.Keys.GenAI.requestMaxTokens]?.description == "512")
  #expect(span.attributes["terra.fm.generation.sampling_mode"]?.description == "top_p")
}

@available(macOS 26.0, iOS 26.0, *)
@Test("FoundationModels wrapper sets provider metadata")
func foundationModelsProviderMetadata() async throws {
  Terra.lockTestingIsolation()
  defer { Terra.unlockTestingIsolation() }

  let harness = SpanHarness()
  defer { harness.tearDown() }

  let backend = MockBackend()
  let session = TerraTracedSession(backend: backend)
  _ = try await session.respond(to: "Hello")

  let span = try #require(harness.finishedSpans().first(where: { $0.name == "gen_ai.inference" }))
  #expect(span.attributes[Terra.Keys.GenAI.providerName]?.description == "apple/foundation-model")
}
}

#else

// FoundationModels is not available on this platform or SDK.
// These tests confirm the module compiles cleanly as a stub.

@Suite("TerraFoundationModels stub", .serialized)
struct TerraFoundationModelsStubTests {
@Test("TerraFoundationModels stub compiles without FoundationModels framework")
func foundationModelsNotAvailable() async {
  let session = TerraTracedSession(modelIdentifier: "apple/stub-model")
  let alias = Terra.TracedSession(modelIdentifier: "apple/alias-model")
  #expect(session.modelIdentifier == "apple/stub-model")
  #expect(alias.modelIdentifier == "apple/alias-model")

  await #expect(throws: TerraFoundationModelsUnavailableError.self) {
    _ = try await session.respond(to: "hello")
  }
}
}

#endif
