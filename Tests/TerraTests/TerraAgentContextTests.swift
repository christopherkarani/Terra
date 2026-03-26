import Testing
@testable import TerraCore

@Suite("AgentContext", .serialized)
struct TerraAgentContextTests {
  @Test("Inference and tool calls inside agent are accumulated on agent span")
  func accumulationInsideAgent() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    _ = try await Terra.agent(name: "planner").execute {
      _ = await Terra.inference(model: "m1") { "ok" }
      _ = await Terra.tool(name: "search", callId: "call-1") { "ok" }
      return "done"
    }

    let spans = support.finishedSpans()
    let agentSpan = try #require(spans.first(where: { $0.name == Terra.SpanNames.agentInvocation }))
    #expect(agentSpan.attributes["terra.agent.inference_count"]?.description == "1")
    #expect(agentSpan.attributes["terra.agent.tool_call_count"]?.description == "1")
    #expect(agentSpan.attributes["terra.agent.models_used"]?.description == "m1")
    #expect(agentSpan.attributes["terra.agent.tools_used"]?.description == "search")
  }

  @Test("Structured Task inherits agent context")
  func structuredTaskInheritsContext() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    _ = try await Terra.agent(name: "planner").execute {
      let task = Task {
        _ = await Terra.tool(name: "structured", callId: "call-1") { "ok" }
      }
      _ = try await task.value
      return "done"
    }

    let spans = support.finishedSpans()
    let agentSpan = try #require(spans.first(where: { $0.name == Terra.SpanNames.agentInvocation }))
    #expect(agentSpan.attributes["terra.agent.tool_call_count"]?.description == "1")
    #expect(agentSpan.attributes["terra.agent.tools_used"]?.description == "structured")
  }

  @Test("Detached Task does not inherit agent context")
  func detachedTaskDoesNotInheritContext() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    _ = try await Terra.agent(name: "planner").execute {
      let task = Task.detached {
        _ = await Terra.tool(name: "detached", callId: "call-1") { "ok" }
      }
      _ = try await task.value
      return "done"
    }

    let spans = support.finishedSpans()
    let agentSpan = try #require(spans.first(where: { $0.name == Terra.SpanNames.agentInvocation }))
    #expect(agentSpan.attributes["terra.agent.tool_call_count"]?.description == "0")
    #expect(agentSpan.attributes["terra.agent.tools_used"]?.description == "")
  }

  @Test("AgentHandle detached helper preserves agent context")
  func detachedHelperPreservesContext() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    _ = try await Terra.agentic(name: "planner") { agent in
      let task = agent.detached {
        _ = await $0.tool("detached-helper", callId: "call-1") { "ok" }
      }
      _ = try await task.value
      return "done"
    }

    let spans = support.finishedSpans()
    let root = try #require(spans.first(where: { $0.name == "planner" }))
    let tool = try #require(spans.first(where: { $0.name == Terra.SpanNames.toolExecution }))

    #expect(root.attributes[Terra.Keys.GenAI.operationName]?.description == Terra.OperationName.invokeAgent.rawValue)
    #expect(root.attributes[Terra.Keys.GenAI.agentName]?.description == "planner")
    #expect(root.attributes["terra.agent.tool_call_count"]?.description == "1")
    #expect(root.attributes["terra.agent.tools_used"]?.description == "detached-helper")
    #expect(tool.parentSpanId?.hexString == root.spanId.hexString)
    #expect(tool.traceId.hexString == root.traceId.hexString)
  }
}
