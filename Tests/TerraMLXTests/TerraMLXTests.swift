import Testing
import TerraMLX
import TerraCore
import OpenTelemetryApi
import OpenTelemetrySdk
import InMemoryExporter

// MARK: - Test Support

/// Sets up a fresh InMemoryExporter + TracerProvider for each test.
/// Uses explicit `tearDown()` instead of `deinit` because Swift Testing
/// doesn't guarantee deterministic deallocation between `@Test` functions.
private struct SpanTestHarness {
  let previousTracerProvider: any TracerProvider
  let spanExporter: InMemoryExporter
  let tracerProvider: TracerProviderSdk

  init() {
    previousTracerProvider = OpenTelemetry.instance.tracerProvider
    spanExporter = InMemoryExporter()
    tracerProvider = TracerProviderSdk()
    tracerProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: spanExporter))
    OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
    // Ensure Terra.Runtime uses this provider instead of a stale override from other tests.
    Terra.install(.init(tracerProvider: tracerProvider, registerProvidersAsGlobal: false))
  }

  func finishedSpans() -> [SpanData] {
    tracerProvider.forceFlush()
    return spanExporter.getFinishedSpanItems()
  }

  func tearDown() {
    OpenTelemetry.registerTracerProvider(tracerProvider: previousTracerProvider)
  }
}

@Suite("TerraMLX Tests", .serialized)
struct TerraMLXTests {
  // MARK: - TerraMLX.traced Tests

  @Test("traced creates a span with the expected model attribute")
  func tracedCreatesSpanWithModel() async throws {
    let h = SpanTestHarness()
    defer { h.tearDown() }

    _ = try await TerraMLX.traced(model: "test-model") {
      "result"
    }

    let spans = h.finishedSpans()
    #expect(spans.count == 1)

    let span = try #require(spans.first)
    #expect(span.attributes[Terra.Keys.GenAI.requestModel]?.description == "test-model")
  }

  @Test("traced sets terra.runtime attribute to mlx")
  func tracedSetsRuntimeAttribute() async throws {
    let h = SpanTestHarness()
    defer { h.tearDown() }

    _ = try await TerraMLX.traced(model: "mlx-community/Llama-3.2-1B") {
      "response"
    }

    let spans = h.finishedSpans()
    let span = try #require(spans.first)
    #expect(span.attributes[Terra.Keys.Terra.runtime]?.description == "mlx")
  }

  @Test("traced sets terra.auto_instrumented attribute to true")
  func tracedSetsAutoInstrumentedAttribute() async throws {
    let h = SpanTestHarness()
    defer { h.tearDown() }

    _ = try await TerraMLX.traced(model: "test-model") {
      42
    }

    let spans = h.finishedSpans()
    let span = try #require(spans.first)
    #expect(span.attributes[Terra.Keys.Terra.autoInstrumented]?.description == "true")
  }

  @Test("traced forwards maxTokens to the span")
  func tracedForwardsMaxTokens() async throws {
    let h = SpanTestHarness()
    defer { h.tearDown() }

    _ = try await TerraMLX.traced(model: "test-model", maxTokens: 256) {
      "result"
    }

    let spans = h.finishedSpans()
    let span = try #require(spans.first)
    #expect(span.attributes[Terra.Keys.GenAI.requestMaxTokens]?.description == "256")
  }

  @Test("traced forwards temperature to the span")
  func tracedForwardsTemperature() async throws {
    let h = SpanTestHarness()
    defer { h.tearDown() }

    _ = try await TerraMLX.traced(model: "test-model", temperature: 0.8) {
      "result"
    }

    let spans = h.finishedSpans()
    let span = try #require(spans.first)
    #expect(span.attributes[Terra.Keys.GenAI.requestTemperature]?.description == "0.8")
  }

  @Test("traced returns the value produced by the closure")
  func tracedReturnsClosureValue() async throws {
    let h = SpanTestHarness()
    defer { h.tearDown() }

    let result = try await TerraMLX.traced(model: "test-model") {
      "the generated text"
    }

    #expect(result == "the generated text")
  }

  @Test("traced propagates errors thrown from the closure")
  func tracedPropagatesErrors() async throws {
    struct GenerationError: Error {}

    let h = SpanTestHarness()
    defer { h.tearDown() }

    do {
      _ = try await TerraMLX.traced(model: "test-model") {
        throw GenerationError()
      }
      Issue.record("Expected GenerationError to be thrown")
    } catch is GenerationError {
      // Expected
    }

    let spans = h.finishedSpans()
    #expect(spans.count == 1)
  }

  @Test("traced span has gen_ai.inference name")
  func tracedSpanHasInferenceName() async throws {
    let h = SpanTestHarness()
    defer { h.tearDown() }

    _ = try await TerraMLX.traced(model: "test-model") { "r" }

    let span = try #require(h.finishedSpans().first)
    #expect(span.name == Terra.SpanNames.inference)
  }

  // MARK: - TerraMLX.recordTokenCount Tests

  @Test("recordTokenCount updates output token attribute on active span")
  func recordTokenCountUpdatesAttribute() async throws {
    let h = SpanTestHarness()
    defer { h.tearDown() }

    _ = try await TerraMLX.traced(model: "test-model") {
      TerraMLX.recordTokenCount(128)
      return "done"
    }

    let span = try #require(h.finishedSpans().first)
    #expect(span.attributes[Terra.Keys.GenAI.usageOutputTokens]?.description == "128")
  }

  // MARK: - TerraMLX.recordFirstToken Tests

  @Test("recordFirstToken adds first_token event on active span")
  func recordFirstTokenAddsEvent() async throws {
    let h = SpanTestHarness()
    defer { h.tearDown() }

    _ = try await TerraMLX.traced(model: "test-model") {
      TerraMLX.recordFirstToken()
      return "done"
    }

    let span = try #require(h.finishedSpans().first)
    let hasFirstTokenEvent = span.events.contains { $0.name == "terra.first_token" }
    #expect(hasFirstTokenEvent)
  }

  // MARK: - Terra.MLX alias

  @Test("Terra.MLX is a valid alias for TerraMLX")
  func terraMLXAliasWorks() async throws {
    let h = SpanTestHarness()
    defer { h.tearDown() }

    _ = try await Terra.MLX.traced(model: "alias-test") { "ok" }

    #expect(h.finishedSpans().count == 1)
  }
}
