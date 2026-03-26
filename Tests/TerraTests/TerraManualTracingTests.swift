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

  @Test("Agentic API keeps child inference and tool spans under one root")
  func agenticAPIKeepsChildSpansUnderOneRoot() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let value = try await Terra.agentic(name: "planner-loop", id: "issue-42") { agent in
      let current = try #require(Terra.currentSpan())
      #expect(current.spanId == agent.spanId)

      let draft = try await agent.infer("child-model", prompt: "plan") { "draft" }
      let docs = try await agent.tool("search", callId: "call-1") { "docs" }
      return draft + docs
    }

    #expect(value == "draftdocs")

    let spans = support.finishedSpans()
    let root = try #require(spans.first(where: { $0.name == "planner-loop" }))
    let inference = try #require(spans.first(where: { $0.name == Terra.SpanNames.inference }))
    let tool = try #require(spans.first(where: { $0.name == Terra.SpanNames.toolExecution }))

    #expect(root.attributes[Terra.Keys.GenAI.operationName]?.description == Terra.OperationName.invokeAgent.rawValue)
    #expect(root.attributes[Terra.Keys.GenAI.agentName]?.description == "planner-loop")
    #expect(root.attributes[Terra.Keys.GenAI.agentID]?.description == "issue-42")
    #expect(root.attributes["terra.agent.inference_count"]?.description == "1")
    #expect(root.attributes["terra.agent.tool_call_count"]?.description == "1")
    #expect(root.attributes["terra.agent.models_used"]?.description == "child-model")
    #expect(root.attributes["terra.agent.tools_used"]?.description == "search")
    #expect(inference.parentSpanId?.hexString == root.spanId.hexString)
    #expect(tool.parentSpanId?.hexString == root.spanId.hexString)
    #expect(inference.traceId.hexString == root.traceId.hexString)
    #expect(tool.traceId.hexString == root.traceId.hexString)
  }

  @Test("SpanHandle detached helper preserves parent trace context")
  func spanHandleDetachedHelperPreservesParentTraceContext() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let span = Terra.startSpan(name: "manual-root", id: "issue-11")
    let task = span.detached { _ in
      try await Terra.tool("search", callId: "call-detached").run { "ok" }
    }

    _ = try await task.value
    span.end()

    let spans = support.finishedSpans()
    let root = try #require(spans.first(where: { $0.name == "manual-root" }))
    let tool = try #require(spans.first(where: { $0.name == Terra.SpanNames.toolExecution }))

    #expect(tool.parentSpanId?.hexString == root.spanId.hexString)
    #expect(tool.traceId.hexString == root.traceId.hexString)
  }

  @Test("SpanHandle detached helper continues when parent span already ended")
  func spanHandleDetachedHelperContinuesWhenParentEnded() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let span = Terra.startSpan(name: "manual-root", id: "issue-12")
    span.end()

    let task = span.detached { _ in
      try await Terra.tool("search", callId: "call-ended-parent").run { "ok" }
    }

    let value = try await task.value
    #expect(value == "ok")

    let spans = support.finishedSpans()
    let tool = try #require(spans.first(where: { $0.name == Terra.SpanNames.toolExecution }))

    #expect(tool.parentSpanId == nil)
    #expect(tool.events.contains(where: { $0.name == "detached.parent.ended" }))
  }

  @Test("AgentHandle infer messages overload records structured prompt attributes")
  func agentHandleInferMessagesOverloadRecordsStructuredPromptAttributes() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let result = try await Terra.agentic(name: "planner-loop", id: "issue-43") { agent in
      try await agent.infer(
        "child-model",
        messages: [
          .init(role: "system", content: "You are a planner."),
          .init(role: "user", content: "Draft a route.")
        ]
      ) { "draft" }
    }

    #expect(result == "draft")

    let spans = support.finishedSpans()
    let root = try #require(spans.first(where: { $0.name == "planner-loop" }))
    let inference = try #require(spans.first(where: { $0.name == Terra.SpanNames.inference }))

    #expect(inference.parentSpanId?.hexString == root.spanId.hexString)
    #expect(inference.traceId.hexString == root.traceId.hexString)
    #expect(inference.attributes[Terra.Keys.GenAI.promptMessageCount]?.description == "2")
    #expect(inference.attributes[Terra.Keys.GenAI.promptRole0]?.description == "system")
  }
}
