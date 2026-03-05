import Testing
@testable import TerraCore

@Suite("TerraTraceable", .serialized)
struct TerraTraceableTests {
  private struct TraceableResponse: Terra.TerraTraceable {
    var terraTokenUsage: Terra.TokenUsage? { .init(input: 11, output: 7) }
    var terraResponseModel: String? { "model@response" }
  }

  @Test("Inference auto-extracts token usage and response model from TerraTraceable return")
  func autoExtractionFromTraceableResult() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    _ = try await Terra.inference(model: "model@request").execute { _ in
      TraceableResponse()
    }

    let span = try #require(support.finishedSpans().first)
    #expect(span.attributes[Terra.Keys.GenAI.usageInputTokens]?.description == "11")
    #expect(span.attributes[Terra.Keys.GenAI.usageOutputTokens]?.description == "7")
    #expect(span.attributes[Terra.Keys.GenAI.responseModel]?.description == "model@response")
  }
}
