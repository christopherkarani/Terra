import Testing
@testable import TerraHTTPInstrument

@Suite("HTTPAIInstrumentation Host Matching")
struct HTTPAIInstrumentationTests {
  @Test("Host boundary match allows exact host and subdomains")
  func hostBoundaryAllowsExactAndSubdomain() {
    #expect(HTTPAIInstrumentation.isHostBoundaryMatch(host: "api.openai.com", target: "api.openai.com"))
    #expect(HTTPAIInstrumentation.isHostBoundaryMatch(host: "foo.api.openai.com", target: "api.openai.com"))
  }

  @Test("Host boundary match rejects suffix confusion")
  func hostBoundaryRejectsSuffixConfusion() {
    #expect(!HTTPAIInstrumentation.isHostBoundaryMatch(host: "evilapi.openai.com", target: "api.openai.com"))
    #expect(!HTTPAIInstrumentation.isHostBoundaryMatch(host: "evil-ai.com", target: "ai.com"))
  }

  @Test("Host boundary match is case-insensitive")
  func hostBoundaryIsCaseInsensitive() {
    #expect(HTTPAIInstrumentation.isHostBoundaryMatch(host: "API.OPENAI.COM", target: "api.openai.com"))
  }
}
