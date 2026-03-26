import Testing
@testable import TerraCore

@Suite("String-first identifiers", .serialized)
struct TerraIdentifierTests {
  @Test("Provider and runtime wrappers preserve raw values")
  func providerAndRuntimeWrappersPreserveRawValues() {
    let provider = Terra.ProviderID("openai")
    let runtime = Terra.RuntimeID("mlx")

    #expect(provider.rawValue == "openai")
    #expect(runtime.rawValue == "mlx")
  }

  @Test("String-first factories remain uniform")
  func stringFirstFactoriesRemainUniform() {
    let infer = Terra.infer("gpt-4o")
    let stream = Terra.stream("gpt-4o")
    let embed = Terra.embed("text-embedding-3-small")
    let tool = Terra.tool("search", callId: "call-7")

    #expect([infer, stream, embed, tool].count == 4)
  }

  @Test("Capabilities expose the workflow-first tracing surface")
  func capabilitiesExposeWorkflowFirstTracingSurface() {
    let capabilities = Terra.capabilities()

    #expect(capabilities.count >= 10)
    #expect(capabilities.contains { $0.entryPoint == "Terra.workflow(name:id:_:)" && $0.preference == .primary })
    #expect(capabilities.contains { $0.entryPoint == "Terra.workflow(name:id:messages:_:)" && $0.preference == .primary })
    #expect(capabilities.contains { $0.entryPoint == "Terra.startSpan(name:id:attributes:)" })
    #expect(capabilities.contains { $0.entryPoint == "Terra.currentSpan()" })
    #expect(!capabilities.contains { $0.preference == .compatibility })
  }

  @Test("Workflow guidance is actionable")
  func workflowGuidanceIsActionable() {
    let guidance = Terra.ask("workflow with tools")

    #expect(guidance.apiToUse.contains("Terra.workflow"))
    #expect(guidance.codeExample.contains("workflow.tool"))
    #expect(!guidance.commonMistakes.isEmpty)
  }
}
