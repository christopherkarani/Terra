import Testing
@testable import TerraCore

@Suite("Loop and playground", .serialized)
struct TerraLoopAndPlaygroundTests {
  @Test("Workflow transcript writes buffered messages back on success")
  func workflowTranscriptWritesBufferedMessagesBackOnSuccess() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    var messages = [Terra.ChatMessage(role: "user", content: "Plan the fix.")]

    let result = try await Terra.workflow(name: "planner", id: "turn-1", messages: &messages) { workflow, transcript in
      workflow.checkpoint("planning")
      await transcript.append(.init(role: "assistant", content: "Draft plan"))
      return await workflow.tool("search", callId: "call-1") { span in
        span.event("tool.search")
        return "ok"
      }
    }

    #expect(result == "ok")
    #expect(messages.count == 2)
    #expect(messages.last?.content == "Draft plan")
    #expect(support.finishedSpans().contains { $0.name == "planner" })
  }

  @Test("Workflow transcript writes buffered messages back after errors")
  func workflowTranscriptWritesBufferedMessagesBackAfterErrors() async {
    enum ExpectedError: Error { case failed }

    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    var messages = [Terra.ChatMessage(role: "user", content: "Plan the fix.")]

    await #expect(throws: ExpectedError.self) {
      try await Terra.workflow(name: "planner", id: "turn-2", messages: &messages) { _, transcript in
        await transcript.append(.init(role: "assistant", content: "Partial draft"))
        throw ExpectedError.failed
      }
    }

    #expect(messages.count == 2)
    #expect(messages.last?.content == "Partial draft")
  }

  @Test("Composable operations expose the active Terra span handle directly")
  func composableOperationsExposeUnderlyingSpanHandleDirectly() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let hasSpan = try await Terra.infer("local-model", prompt: "Hello").run { span in
      !span.spanId.isEmpty
    }

    #expect(hasSpan)
  }

  @Test("Playground scenarios are listed and runnable")
  func playgroundScenariosAreListedAndRunnable() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let playground = Terra.playground()
    let scenarios = playground.scenarios()
    let result = try await playground.run("workflow-basic")

    #expect(scenarios.count >= 6)
    #expect(scenarios.contains { $0.id == "workflow-basic" })
    #expect(scenarios.contains { $0.id == "workflow-messages" })
    #expect(result.summary.contains("Terra.workflow"))
    #expect(result.recordedEvents.contains("workflow.start"))
    #expect(result.spanTree?.contains("playground.workflow") == true)
  }
}
