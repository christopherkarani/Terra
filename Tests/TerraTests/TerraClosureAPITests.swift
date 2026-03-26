import Testing
@testable import TerraCore

@Suite("Closure-first API", .serialized)
struct TerraClosureAPITests {
  @Test("Inference closure-only overload returns body result")
  func inferenceClosureOnlyOverload() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let value = await Terra.inference(model: "local/model") {
      "ok"
    }

    #expect(value == "ok")
    let span = try #require(support.finishedSpans().first)
    #expect(span.name == Terra.SpanNames.inference)
  }

  @Test("Inference trace overload allows custom telemetry")
  func inferenceTraceOverload() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let value = await Terra.inference(model: "local/model") { trace in
      trace.attribute(Terra.Key.provider, "unit-test")
      return "ok"
    }

    #expect(value == "ok")
    let span = try #require(support.finishedSpans().first)
    #expect(span.attributes[Terra.Keys.GenAI.providerName]?.description == "unit-test")
  }

  @Test("Nested closure-first spans preserve parent-child relationships")
  func nestedSpanParentChild() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    _ = await Terra.agent(name: "planner") {
      await Terra.inference(model: "local/model") { "ok" }
    }

    let spans = support.finishedSpans()
    let parent = try #require(spans.first(where: { $0.name == Terra.SpanNames.agentInvocation }))
    let child = try #require(spans.first(where: { $0.name == Terra.SpanNames.inference }))
    #expect(child.traceId.hexString == parent.traceId.hexString)
    #expect(child.parentSpanId?.hexString == parent.spanId.hexString)
  }

  @Test("CancellationError is rethrown and not marked as span failure")
  func cancellationNotRecordedAsFailure() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    await #expect(throws: CancellationError.self) {
      _ = try await Terra.inference(model: "local/model") {
        throw CancellationError()
      }
    }

    let span = try #require(support.finishedSpans().first)
    #expect(!span.status.isError)
  }

  @Test("stream/tool/embedding/safety closure-first overloads create spans")
  func remainingFactoryOverloads() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    _ = await Terra.stream(model: "local/model") { "ok" }
    _ = await Terra.tool(name: "search", callId: "call-1") { "ok" }
    _ = await Terra.embedding(model: "embed-model") { "ok" }
    _ = await Terra.safetyCheck(name: "toxicity", subject: "hello") { "ok" }

    let spans = support.finishedSpans()
    #expect(spans.contains { $0.name == Terra.SpanNames.inference })
    #expect(spans.contains { $0.name == Terra.SpanNames.toolExecution })
    #expect(spans.contains { $0.name == Terra.SpanNames.embedding })
    #expect(spans.contains { $0.name == Terra.SpanNames.safetyCheck })
  }
}
