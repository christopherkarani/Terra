import Testing
import OpenTelemetrySdk
@testable import TerraCore

@Suite("Terra Privacy Audit", .serialized)
struct TerraPrivacyAuditTests {
  private enum ExpectedError: Error, CustomStringConvertible {
    case failed

    var description: String {
      "privacy-audit-secret-error"
    }
  }

  @Test("Inference prompt is not captured by default under redacted-like policy")
  func inferencePromptDefaultSafe() async throws {
    let secret = "prompt-secret-123"
    let span = try await captureSpan(
      privacy: .init(contentPolicy: .optIn, redaction: .hashHMACSHA256)
    ) {
      _ = try await Terra.inference(model: "audit-model", prompt: secret).execute { "ok" }
    }

    #expect(span.attributes[Terra.Keys.Terra.promptLength] == nil)
    #expect(span.attributes[Terra.Keys.Terra.promptHMACSHA256] == nil)
    #expect(span.attributes.values.allSatisfy { !$0.description.contains(secret) })
  }

  @Test("Safety check subject is not captured by default under redacted-like policy")
  func safetySubjectDefaultSafe() async throws {
    let secret = "subject-secret-456"
    let span = try await captureSpan(
      privacy: .init(contentPolicy: .optIn, redaction: .hashHMACSHA256)
    ) {
      _ = try await Terra.safetyCheck(name: "toxicity", subject: secret).execute { "ok" }
    }

    #expect(span.attributes[Terra.Keys.Terra.safetySubjectLength] == nil)
    #expect(span.attributes[Terra.Keys.Terra.safetySubjectHMACSHA256] == nil)
    #expect(span.attributes.values.allSatisfy { !$0.description.contains(secret) })
  }

  @Test("includeContent overrides only one call and does not mutate global behavior")
  func includeContentIsPerCallOnly() async throws {
    let secret = "content-override-secret"
    let privacy = Terra.Privacy(contentPolicy: .optIn, redaction: .hashHMACSHA256)

    let first = try await captureSpan(privacy: privacy) {
      _ = try await Terra.inference(model: "audit-model", prompt: secret).execute { "ok" }
    }
    #expect(first.attributes[Terra.Keys.Terra.promptHMACSHA256] == nil)

    let second = try await captureSpan(privacy: privacy) {
      _ = try await Terra.inference(model: "audit-model", prompt: secret).includeContent().execute { "ok" }
    }
    #expect(second.attributes[Terra.Keys.Terra.promptHMACSHA256] != nil)
    #expect(second.attributes.values.allSatisfy { !$0.description.contains(secret) })

    let third = try await captureSpan(privacy: privacy) {
      _ = try await Terra.inference(model: "audit-model", prompt: secret).execute { "ok" }
    }
    #expect(third.attributes[Terra.Keys.Terra.promptHMACSHA256] == nil)
  }

  @Test("CapturePolicy.includeContent captures prompt for composable API calls")
  func capturePolicyIncludeContentCapturesPrompt() async throws {
    let secret = "capture-policy-secret"
    let privacy = Terra.Privacy(contentPolicy: .optIn, redaction: .hashHMACSHA256)

    let span = try await captureSpan(privacy: privacy) {
      _ = try await Terra
        .infer("audit-model", prompt: secret)
        .capture(.includeContent)
        .run { "ok" }
    }

    #expect(span.attributes[Terra.Keys.Terra.promptHMACSHA256] != nil)
    #expect(span.attributes.values.allSatisfy { !$0.description.contains(secret) })
  }

  @Test("recordError omits exception.message under redacted-like policy")
  func recordErrorIsGatedByPrivacy() async throws {
    let span = try await captureErrorSpan(
      privacy: .init(contentPolicy: .optIn, redaction: .hashHMACSHA256)
    ) {
      _ = try await Terra.inference(model: "audit-model", prompt: "hello").execute { _ in
        throw ExpectedError.failed
      }
    }

    let exception = try #require(span.events.first(where: { $0.name == "exception" }))
    #expect(exception.attributes["exception.type"]?.description == String(reflecting: ExpectedError.self))
    #expect(exception.attributes["exception.message"] == nil)
  }

  @Test("Agent context accumulates names only and excludes content")
  func agentContextNamesOnly() async throws {
    let secret = "agent-secret-content"
    let spans = try await captureSpans(
      privacy: .init(contentPolicy: .optIn, redaction: .hashHMACSHA256)
    ) {
      _ = try await Terra.agent(name: "planner") {
        _ = try await Terra.inference(model: "planner-model", prompt: secret) { "ok" }
        _ = try await Terra.tool(name: "search", callID: "call-1") { "ok" }
        return "done"
      }
    }
    let span = try #require(spans.first(where: { $0.name == Terra.SpanNames.agentInvocation }))

    #expect(span.attributes["terra.agent.tools_used"]?.description == "search")
    #expect(span.attributes["terra.agent.models_used"]?.description == "planner-model")
    #expect(span.attributes.values.allSatisfy { !$0.description.contains(secret) })
  }

  @Test("Streaming traces capture counts without chunk content")
  func streamingChunkContentNotCaptured() async throws {
    let secret = "streaming-secret-content"
    let span = try await captureSpan(
      privacy: .init(contentPolicy: .optIn, redaction: .hashHMACSHA256)
    ) {
      _ = try await Terra.stream(model: "stream-model", prompt: secret).execute { trace in
        trace.chunk(tokens: 2)
        return "ok"
      }
    }

    #expect(span.attributes[Terra.Keys.Terra.streamChunkCount]?.description == "1")
    #expect(span.attributes[Terra.Keys.Terra.streamOutputTokens]?.description == "2")
    #expect(span.attributes.values.allSatisfy { !$0.description.contains(secret) })
  }

  private func captureSpan(
    privacy: Terra.Privacy,
    _ body: @Sendable () async throws -> Void
  ) async throws -> SpanData {
    let spans = try await captureSpans(privacy: privacy, body)
    return try #require(spans.first)
  }

  private func captureSpans(
    privacy: Terra.Privacy,
    _ body: @Sendable () async throws -> Void
  ) async throws -> [SpanData] {
    let support = TerraTestSupport()
    Terra.install(
      .init(
        privacy: privacy,
        tracerProvider: support.tracerProvider,
        registerProvidersAsGlobal: false
      )
    )

    try await body()
    return support.finishedSpans()
  }

  private func captureErrorSpan(
    privacy: Terra.Privacy,
    _ body: @Sendable () async throws -> Void
  ) async throws -> SpanData {
    let support = TerraTestSupport()
    Terra.install(
      .init(
        privacy: privacy,
        tracerProvider: support.tracerProvider,
        registerProvidersAsGlobal: false
      )
    )

    await #expect(throws: ExpectedError.self) {
      try await body()
    }
    return try #require(support.finishedSpans().first)
  }
}
