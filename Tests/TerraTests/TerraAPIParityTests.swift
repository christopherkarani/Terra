import Testing
import OpenTelemetrySdk
@testable import TerraCore

@Suite("Terra API Parity", .serialized)
final class TerraAPIParityTests {
  private enum ExpectedError: Error, CustomStringConvertible {
    case failed

    var description: String {
      "parity-failure"
    }
  }

  @Test("Inference closure-first and builder-execute paths are equivalent")
  func inferenceParity() async throws {
    try await assertParity(
      expectedSpanName: Terra.SpanNames.inference,
      expectedOperation: Terra.OperationName.inference.rawValue,
      expectedAttributeKey: Terra.Keys.GenAI.requestModel,
      expectedAttributeValue: "parity-model",
      closureCall: {
        _ = try await Terra.inference(model: "parity-model", prompt: "hello") { "ok" }
      },
      builderCall: {
        _ = try await Terra.inference(model: "parity-model", prompt: "hello").execute { "ok" }
      },
      closureErrorCall: {
        _ = try await Terra.inference(model: "parity-model", prompt: "hello") { () -> String in
          throw ExpectedError.failed
        }
      },
      builderErrorCall: {
        _ = try await Terra.inference(model: "parity-model", prompt: "hello").execute { () -> String in
          throw ExpectedError.failed
        }
      }
    )
  }

  @Test("Streaming closure-first and builder-execute paths are equivalent")
  func streamParity() async throws {
    try await assertParity(
      expectedSpanName: Terra.SpanNames.inference,
      expectedOperation: Terra.OperationName.inference.rawValue,
      expectedAttributeKey: Terra.Keys.GenAI.requestModel,
      expectedAttributeValue: "parity-stream-model",
      closureCall: {
        _ = try await Terra.stream(model: "parity-stream-model", prompt: "hello") { trace in
          trace.chunk(tokens: 3)
          return "ok"
        }
      },
      builderCall: {
        _ = try await Terra.stream(model: "parity-stream-model", prompt: "hello").execute { trace in
          trace.chunk(tokens: 3)
          return "ok"
        }
      },
      closureErrorCall: {
        _ = try await Terra.stream(model: "parity-stream-model", prompt: "hello") { _ in
          throw ExpectedError.failed
        }
      },
      builderErrorCall: {
        _ = try await Terra.stream(model: "parity-stream-model", prompt: "hello").execute { _ in
          throw ExpectedError.failed
        }
      }
    )
  }

  @Test("Agent closure-first and builder-execute paths are equivalent")
  func agentParity() async throws {
    try await assertParity(
      expectedSpanName: Terra.SpanNames.agentInvocation,
      expectedOperation: Terra.OperationName.invokeAgent.rawValue,
      expectedAttributeKey: Terra.Keys.GenAI.agentName,
      expectedAttributeValue: "parity-agent",
      closureCall: {
        _ = try await Terra.agent(name: "parity-agent", id: "agent-1") { "ok" }
      },
      builderCall: {
        _ = try await Terra.agent(name: "parity-agent", id: "agent-1").execute { "ok" }
      },
      closureErrorCall: {
        _ = try await Terra.agent(name: "parity-agent", id: "agent-1") { _ in
          throw ExpectedError.failed
        }
      },
      builderErrorCall: {
        _ = try await Terra.agent(name: "parity-agent", id: "agent-1").execute { _ in
          throw ExpectedError.failed
        }
      }
    )
  }

  @Test("Tool closure-first and builder-execute paths are equivalent")
  func toolParity() async throws {
    try await assertParity(
      expectedSpanName: Terra.SpanNames.toolExecution,
      expectedOperation: Terra.OperationName.executeTool.rawValue,
      expectedAttributeKey: Terra.Keys.GenAI.toolName,
      expectedAttributeValue: "parity-tool",
      closureCall: {
        _ = try await Terra.tool(name: "parity-tool", callId: "call-1", type: "http") { "ok" }
      },
      builderCall: {
        _ = try await Terra.tool(name: "parity-tool", callId: "call-1", type: "http").execute { "ok" }
      },
      closureErrorCall: {
        _ = try await Terra.tool(name: "parity-tool", callId: "call-1", type: "http") { _ in
          throw ExpectedError.failed
        }
      },
      builderErrorCall: {
        _ = try await Terra.tool(name: "parity-tool", callId: "call-1", type: "http").execute { _ in
          throw ExpectedError.failed
        }
      }
    )
  }

  @Test("Embedding closure-first and builder-execute paths are equivalent")
  func embeddingParity() async throws {
    try await assertParity(
      expectedSpanName: Terra.SpanNames.embedding,
      expectedOperation: Terra.OperationName.embeddings.rawValue,
      expectedAttributeKey: Terra.Keys.GenAI.requestModel,
      expectedAttributeValue: "parity-embed-model",
      closureCall: {
        _ = try await Terra.embedding(model: "parity-embed-model", inputCount: 4) { "ok" }
      },
      builderCall: {
        _ = try await Terra.embedding(model: "parity-embed-model", inputCount: 4).execute { "ok" }
      },
      closureErrorCall: {
        _ = try await Terra.embedding(model: "parity-embed-model", inputCount: 4) { _ in
          throw ExpectedError.failed
        }
      },
      builderErrorCall: {
        _ = try await Terra.embedding(model: "parity-embed-model", inputCount: 4).execute { _ in
          throw ExpectedError.failed
        }
      }
    )
  }

  @Test("Safety check closure-first and builder-execute paths are equivalent")
  func safetyParity() async throws {
    try await assertParity(
      expectedSpanName: Terra.SpanNames.safetyCheck,
      expectedOperation: Terra.OperationName.safetyCheck.rawValue,
      expectedAttributeKey: Terra.Keys.Terra.safetyCheckName,
      expectedAttributeValue: "parity-safety",
      closureCall: {
        _ = try await Terra.safetyCheck(name: "parity-safety", subject: "content") { "ok" }
      },
      builderCall: {
        _ = try await Terra.safetyCheck(name: "parity-safety", subject: "content").execute { "ok" }
      },
      closureErrorCall: {
        _ = try await Terra.safetyCheck(name: "parity-safety", subject: "content") { _ in
          throw ExpectedError.failed
        }
      },
      builderErrorCall: {
        _ = try await Terra.safetyCheck(name: "parity-safety", subject: "content").execute { _ in
          throw ExpectedError.failed
        }
      }
    )
  }

  private func assertParity(
    expectedSpanName: String,
    expectedOperation: String,
    expectedAttributeKey: String,
    expectedAttributeValue: String,
    closureCall: @Sendable () async throws -> Void,
    builderCall: @Sendable () async throws -> Void,
    closureErrorCall: @Sendable () async throws -> Void,
    builderErrorCall: @Sendable () async throws -> Void
  ) async throws {
    let closureSpan = try await captureSpan(closureCall)
    let builderSpan = try await captureSpan(builderCall)

    #expect(closureSpan.name == expectedSpanName)
    #expect(builderSpan.name == expectedSpanName)
    #expect(closureSpan.attributes[Terra.Keys.GenAI.operationName]?.description == expectedOperation)
    #expect(builderSpan.attributes[Terra.Keys.GenAI.operationName]?.description == expectedOperation)
    #expect(closureSpan.attributes[expectedAttributeKey]?.description == expectedAttributeValue)
    #expect(builderSpan.attributes[expectedAttributeKey]?.description == expectedAttributeValue)

    let closureErrorSpan = try await captureErrorSpan(closureErrorCall)
    let builderErrorSpan = try await captureErrorSpan(builderErrorCall)

    let closureException = closureErrorSpan.events.first(where: { $0.name == "exception" })
    let builderException = builderErrorSpan.events.first(where: { $0.name == "exception" })
    #expect(closureException != nil)
    #expect(builderException != nil)
    #expect(closureException?.attributes["exception.type"]?.description == builderException?.attributes["exception.type"]?.description)
    #expect(closureException?.attributes["exception.message"]?.description == builderException?.attributes["exception.message"]?.description)
  }

  private func captureSpan(
    _ call: @Sendable () async throws -> Void
  ) async throws -> SpanData {
    Terra.resetOpenTelemetryForTesting()
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    try await call()
    return try #require(support.finishedSpans().first)
  }

  private func captureErrorSpan(
    _ call: @Sendable () async throws -> Void
  ) async throws -> SpanData {
    Terra.resetOpenTelemetryForTesting()
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    await #expect(throws: ExpectedError.self) {
      try await call()
    }

    return try #require(support.finishedSpans().first)
  }
}
