import Testing
@testable import TerraCore

@Suite("Terra Key V3", .serialized)
struct TerraKeyV3TopLevelTests {
@Test("Terra.Key.model has correct OTel name")
func keyModelName() {
  #expect(Terra.Key.model.name == "gen_ai.request.model")
}

@Test("Terra.Key.inputTokens has correct OTel name")
func keyInputTokens() {
  #expect(Terra.Key.inputTokens.name == "gen_ai.usage.input_tokens")
}
}
