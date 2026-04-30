import Testing
@testable import TerraCore

@Suite("WorkflowContext", .serialized)
struct TerraAgentContextTests {
  private enum ExpectedAgentError: Error {
    case failed
  }

  @Test("Inference and tool calls inside workflow are accumulated on workflow span")
  func accumulationInsideWorkflow() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    _ = try await Terra.workflow(name: "planner") { workflow in
      _ = await workflow.infer("m1") { "ok" }
      _ = await workflow.tool("search", callId: "call-1") { "ok" }
      return "done"
    }

    let spans = support.finishedSpans()
    let workflowSpan = try #require(spans.first(where: { $0.name == "planner" }))
    #expect(workflowSpan.attributes["terra.workflow.inference_count"]?.description == "1")
    #expect(workflowSpan.attributes["terra.workflow.tool_call_count"]?.description == "1")
    #expect(workflowSpan.attributes["terra.workflow.models_used"]?.description == "m1")
    #expect(workflowSpan.attributes["terra.workflow.tools_used"]?.description == "search")
  }

  @Test("Structured Task inherits workflow context")
  func structuredTaskInheritsContext() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    _ = try await Terra.workflow(name: "planner") { workflow in
      let task = Task {
        _ = await workflow.tool("structured", callId: "call-1") { "ok" }
      }
      _ = try await task.value
      return "done"
    }

    let spans = support.finishedSpans()
    let workflowSpan = try #require(spans.first(where: { $0.name == "planner" }))
    #expect(workflowSpan.attributes["terra.workflow.tool_call_count"]?.description == "1")
    #expect(workflowSpan.attributes["terra.workflow.tools_used"]?.description == "structured")
  }

  @Test("Detached Task does not inherit workflow context")
  func detachedTaskDoesNotInheritContext() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    _ = try await Terra.workflow(name: "planner") { _ in
      let task = Task.detached {
        _ = await Terra.tool(name: "detached", callId: "call-1") { "ok" }
      }
      _ = try await task.value
      return "done"
    }

    let spans = support.finishedSpans()
    let workflowSpan = try #require(spans.first(where: { $0.name == "planner" }))
    #expect(workflowSpan.attributes["terra.workflow.tool_call_count"]?.description == "0")
    #expect(workflowSpan.attributes["terra.workflow.tools_used"]?.description == "")
  }

  @Test("SpanHandle detached helper preserves workflow context")
  func detachedHelperPreservesContext() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    _ = try await Terra.workflow(name: "planner") { workflow in
      let task = workflow.detached {
        _ = await $0.tool("detached-helper", callId: "call-1") { "ok" }
      }
      _ = try await task.value
      return "done"
    }

    let spans = support.finishedSpans()
    let root = try #require(spans.first(where: { $0.name == "planner" }))
    let tool = try #require(spans.first(where: { $0.name == Terra.SpanNames.toolExecution }))

    #expect(root.attributes["terra.workflow.name"]?.description == "planner")
    #expect(root.attributes["terra.workflow.tool_call_count"]?.description == "1")
    #expect(root.attributes["terra.workflow.tools_used"]?.description == "detached-helper")
    #expect(tool.parentSpanId?.hexString == root.spanId.hexString)
    #expect(tool.traceId.hexString == root.traceId.hexString)
  }

  @Test("Agent rollups are emitted when body throws")
  func agentRollupsAreEmittedWhenBodyThrows() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    await #expect(throws: ExpectedAgentError.self) {
      try await Terra.agent("planner").run {
        _ = await Terra.tool("search", callId: "call-1").run { "ok" }
        throw ExpectedAgentError.failed
      }
    }

    let spans = support.finishedSpans()
    let agent = try #require(spans.first(where: { $0.name == Terra.SpanNames.agentInvocation }))
    #expect(agent.status.isError)
    #expect(agent.attributes["terra.agent.tool_call_count"]?.description == "1")
    #expect(agent.attributes["terra.agent.tools_used"]?.description == "search")
  }
}
