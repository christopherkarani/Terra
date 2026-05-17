import Testing
import TerraLlama
@testable import TerraCore

@Suite("TerraLlama wrapper", .serialized)
struct TerraLlamaWrapperTests {
  @Test("TerraLlama is intentionally an internal package target")
  func internalSurfaceExpectation() {
    #expect(TerraLlama.apiSurface == .internalPackageTarget)
  }

  @Test("TerraLlama traced sets provider metadata")
  func providerMetadata() async throws {
    let support = TerraTestSupport()
    defer { support.tearDown() }
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    _ = await TerraLlama.traced(model: "llama-3.2") { trace in
      trace.chunk(tokens: 2)
      return "ok"
    }

    let span = try #require(support.finishedSpans().first)
    #expect(span.attributes[Terra.Keys.GenAI.providerName]?.description == "llama.cpp")
  }
}
