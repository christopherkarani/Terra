import Testing
@testable import TerraCore

@Suite("Manual tracing", .serialized)
struct TerraManualTracingTests {
  @Test("Current span is nil outside tracing")
  func currentSpanIsNilOutsideTracing() {
    #expect(Terra.currentSpan() == nil)
    #expect(!Terra.isTracing())
  }

  @Test("Trace exports an active span and preserves the return value")
  func traceExportsAnActiveSpanAndPreservesTheReturnValue() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let value = try await Terra.trace(name: "agentic-workflow", id: "issue-42") { span in
      #expect(Terra.isTracing())

      let current = try #require(Terra.currentSpan())
      #expect(current.spanId == span.spanId)
      #expect(current.traceId == span.traceId)
      #expect(current.parentId == nil)

      span.event("start")
      span.attribute("phase", "planning")
      return "ok"
    }

    #expect(value == "ok")
    #expect(Terra.currentSpan() == nil)
    #expect(!Terra.isTracing())

    let exported = try #require(support.finishedSpans().first(where: { $0.name == "agentic-workflow" }))
    #expect(exported.attributes["terra.trace.id"]?.description == "issue-42")
    #expect(exported.attributes["phase"]?.description == "planning")
    #expect(exported.events.map(\.name) == ["start"])
  }

  @Test("Nested trace spans expose parent context")
  func nestedTraceSpansExposeParentContext() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    try await Terra.trace(name: "outer", id: "issue-7") { outer in
      let outerCurrent = try #require(Terra.currentSpan())
      #expect(outerCurrent.spanId == outer.spanId)

      try await Terra.trace(name: "inner") { inner in
        let innerCurrent = try #require(Terra.currentSpan())
        #expect(innerCurrent.spanId == inner.spanId)
        #expect(innerCurrent.parentId == outer.spanId)
        return ()
      }
    }

    let spans = support.finishedSpans()
    let outer = try #require(spans.first(where: { $0.name == "outer" }))
    let inner = try #require(spans.first(where: { $0.name == "inner" }))

    #expect(inner.traceId.hexString == outer.traceId.hexString)
    #expect(inner.parentSpanId?.hexString == outer.spanId.hexString)
  }

  @Test("startSpan activates the current task context for later Terra operations")
  func startSpanActivatesTheCurrentTaskContextForLaterOperations() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let span = Terra.startSpan(name: "manual-root", id: "issue-9")

    let current = try #require(Terra.currentSpan())
    #expect(current.spanId == span.spanId)

    _ = await Terra.infer("child-model", prompt: "hello").run { _ in
      "ok"
    }

    span.end()

    let spans = support.finishedSpans()
    let parent = try #require(spans.first(where: { $0.name == "manual-root" }))
    let child = try #require(spans.first(where: { $0.name == Terra.SpanNames.inference }))

    #expect(child.traceId.hexString == parent.traceId.hexString)
    #expect(child.parentSpanId?.hexString == parent.spanId.hexString)
  }

  @Test("Tool-call guidance recommends explicit span lifecycle")
  func toolCallGuidanceRecommendsExplicitSpanLifecycle() {
    let guidance = Terra.ask("How do I trace a tool call that happens after streaming?")

    #expect(guidance.apiToUse.contains("Terra.startSpan"))
    #expect(guidance.codeExample.contains("Terra.tool"))
    #expect(guidance.commonMistakes.contains(where: { $0.contains("closure") }))
  }
}
