import Testing
@testable import TerraCore

@Suite("Typed Identifiers", .serialized)
struct TerraIdentifierTests {
  @Test("IDs preserve rawValue with explicit initializers")
  func idsPreserveRawValue() {
    let model = Terra.ModelID("local/llama")
    #expect(model.rawValue == "local/llama")

    let provider = Terra.ProviderID("openai")
    #expect(provider.rawValue == "openai")

    let runtime = Terra.RuntimeID("mlx")
    #expect(runtime.rawValue == "mlx")

    let callID = Terra.ToolCallID("call-1")
    #expect(callID.rawValue == "call-1")
  }

  @Test("IDs do not expose legacy string-protocol conveniences")
  func idsDoNotExposeLegacyStringProtocolConveniences() {
    let model = Terra.ModelID("local/llama")
    let provider = Terra.ProviderID("openai")
    let runtime = Terra.RuntimeID("mlx")
    let callID = Terra.ToolCallID("call-1")

    #expect((model as Any) is any ExpressibleByStringLiteral == false)
    #expect((provider as Any) is any ExpressibleByStringLiteral == false)
    #expect((runtime as Any) is any ExpressibleByStringLiteral == false)
    #expect((callID as Any) is any ExpressibleByStringLiteral == false)

    #expect((model as Any) is any CustomStringConvertible == false)
    #expect((provider as Any) is any CustomStringConvertible == false)
    #expect((runtime as Any) is any CustomStringConvertible == false)
    #expect((callID as Any) is any CustomStringConvertible == false)

    #expect((model as Any) is any RawRepresentable == false)
    #expect((provider as Any) is any RawRepresentable == false)
    #expect((runtime as Any) is any RawRepresentable == false)
    #expect((callID as Any) is any RawRepresentable == false)
  }

  @Test("ToolCallID init() generates a non-empty identifier")
  func toolCallIDDefaultInitIsNonEmpty() {
    let callID = Terra.ToolCallID()
    #expect(!callID.rawValue.isEmpty)
  }
}
