import Testing
@testable import TerraCore

@Suite("Loop and playground", .serialized)
struct TerraLoopAndPlaygroundTests {
  @Test("Loop writes buffered transcript back on success")
  func loopWritesBufferedTranscriptBackOnSuccess() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    var messages = [Terra.ChatMessage(role: "user", content: "Plan the fix.")]

    let result = try await Terra.loop(name: "planner", id: "turn-1", messages: &messages) { loop in
      loop.checkpoint("planning")
      await loop.appendMessage(.init(role: "assistant", content: "Draft plan"))
      return await loop.tool("search", callId: "call-1") { trace in
        trace.event("tool.search")
        return "ok"
      }
    }

    #expect(result == "ok")
    #expect(messages.count == 2)
    #expect(messages.last?.content == "Draft plan")
    #expect(support.finishedSpans().contains { $0.name == "planner" })
  }

  @Test("Loop writes buffered transcript back after errors")
  func loopWritesBufferedTranscriptBackAfterErrors() async {
    enum ExpectedError: Error { case failed }

    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    var messages = [Terra.ChatMessage(role: "user", content: "Plan the fix.")]

    await #expect(throws: ExpectedError.self) {
      try await Terra.loop(name: "planner", id: "turn-2", messages: &messages) { loop in
        await loop.appendMessage(.init(role: "assistant", content: "Partial draft"))
        throw ExpectedError.failed
      }
    }

    #expect(messages.count == 2)
    #expect(messages.last?.content == "Partial draft")
  }

  @Test("Composable trace handles expose the active Terra span when Terra owns it")
  func traceHandlesExposeUnderlyingSpan() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let hasSpan = try await Terra.infer("local-model", prompt: "Hello").run { trace in
      trace.span?.spanId.isEmpty == false
    }

    #expect(hasSpan)
  }

  @Test("Playground scenarios are listed and runnable")
  func playgroundScenariosAreListedAndRunnable() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let playground = Terra.playground()
    let scenarios = playground.scenarios()
    let result = try await playground.run("trace-basic")

    #expect(scenarios.count >= 6)
    #expect(scenarios.contains { $0.id == "trace-basic" })
    #expect(scenarios.contains { $0.id == "loop-messages" })
    #expect(result.summary.contains("Terra.trace"))
    #expect(result.recordedEvents.contains("trace.start"))
    #expect(result.spanTree?.contains("playground.trace") == true)
  }
}
