import Testing
@testable import TerraCore

@Suite("String-first identifiers", .serialized)
struct TerraIdentifierTests {
  @Test("Provider and runtime wrappers preserve raw values")
  func providerAndRuntimeWrappersPreserveRawValues() {
    let model = Terra.ModelID("gpt-4o")
    let toolCall = Terra.ToolCallID("call-1")
    let generatedToolCall = Terra.ToolCallID()
    let provider = Terra.ProviderID("openai")
    let runtime = Terra.RuntimeID("mlx")

    #expect(model.rawValue == "gpt-4o")
    #expect(toolCall.rawValue == "call-1")
    #expect(!generatedToolCall.rawValue.isEmpty)
    #expect(provider.rawValue == "openai")
    #expect(runtime.rawValue == "mlx")
  }

  @Test("Deprecated wrappers bridge into the string-first API")
  func deprecatedWrappersBridgeIntoStringFirstApi() {
    let infer = Terra.infer(Terra.ModelID("gpt-4o"))
    let stream = Terra.stream(Terra.ModelID("gpt-4o"))
    let embed = Terra.embed(Terra.ModelID("text-embedding-3-small"))
    let tool = Terra.tool("search", callID: Terra.ToolCallID("call-7"))

    #expect([infer, stream, embed, tool].count == 4)
  }

  @Test("Capabilities expose the new string-first tracing surface")
  func capabilitiesExposeStringFirstTracingSurface() {
    let capabilities = Terra.capabilities()

    #expect(capabilities.count >= 5)
    #expect(capabilities.contains { $0.entryPoint == "Terra.trace(name:id:_:)" })
    #expect(capabilities.contains { $0.entryPoint == "Terra.startSpan(name:id:attributes:)" })
    #expect(capabilities.contains { $0.entryPoint == "Terra.currentSpan()" })
  }

  @Test("Agentic workflow guidance is actionable")
  func agenticWorkflowGuidanceIsActionable() {
    let guidance = Terra.ask("agentic workflow")

    #expect(guidance.apiToUse.contains("Terra.agentic"))
    #expect(guidance.codeExample.contains("agent.tool"))
    #expect(!guidance.commonMistakes.isEmpty)
  }
}
