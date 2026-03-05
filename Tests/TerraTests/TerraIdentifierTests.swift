import Testing
@testable import TerraCore

@Suite("Typed Identifiers", .serialized)
struct TerraIdentifierTests {
  @Test("IDs support string literals and preserve rawValue")
  func idsSupportStringLiterals() {
    let model: Terra.ModelID = "local/llama"
    #expect(model.rawValue == "local/llama")

    let provider: Terra.ProviderID = "openai"
    #expect(provider.rawValue == "openai")

    let runtime: Terra.RuntimeID = "mlx"
    #expect(runtime.rawValue == "mlx")

    let callID: Terra.ToolCallID = "call-1"
    #expect(callID.rawValue == "call-1")
  }

  @Test("ToolCallID init() generates a non-empty identifier")
  func toolCallIDDefaultInitIsNonEmpty() {
    let callID = Terra.ToolCallID()
    #expect(!callID.rawValue.isEmpty)
  }
}

