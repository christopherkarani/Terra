import Testing
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import TerraTracedMacroPlugin

private let testMacros: [String: any Macro.Type] = [
  "Traced": TracedMacro.self,
]

@Suite("TracedMacro expansion", .serialized)
struct TracedMacroExpansionTopLevelTests {
@Test("Model macro with no matching params expands with model only")
func modelMacroNoMatchingParams() {
  assertMacroExpansion(
    """
    @Traced(model: "llama")
    func generate(topic: String) async throws -> String {
      try await doGenerate(topic)
    }
    """,
    expandedSource: """
    func generate(topic: String) async throws -> String {
      return try await Terra.infer("llama").run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(topic)
      }
    }
    """,
    macros: testMacros
  )
}
}

@Test("Model macro auto-detects prompt parameter")
func modelMacroDetectsPrompt() {
  assertMacroExpansion(
    """
    @Traced(model: "llama")
    func generate(prompt: String) async throws -> String {
      try await doGenerate(prompt)
    }
    """,
    expandedSource: """
    func generate(prompt: String) async throws -> String {
      return try await Terra.infer("llama", prompt: prompt).run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(prompt)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Model macro auto-detects input as prompt alias")
func modelMacroDetectsInputAlias() {
  assertMacroExpansion(
    """
    @Traced(model: "llama")
    func generate(input: String) async throws -> String {
      try await doGenerate(input)
    }
    """,
    expandedSource: """
    func generate(input: String) async throws -> String {
      return try await Terra.infer("llama", prompt: input).run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(input)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Model macro auto-detects query as prompt alias")
func modelMacroDetectsQueryAlias() {
  assertMacroExpansion(
    """
    @Traced(model: "llama")
    func generate(query: String) async throws -> String {
      try await doGenerate(query)
    }
    """,
    expandedSource: """
    func generate(query: String) async throws -> String {
      return try await Terra.infer("llama", prompt: query).run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(query)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Model macro auto-detects text as prompt alias")
func modelMacroDetectsTextAlias() {
  assertMacroExpansion(
    """
    @Traced(model: "llama")
    func generate(text: String) async throws -> String {
      try await doGenerate(text)
    }
    """,
    expandedSource: """
    func generate(text: String) async throws -> String {
      return try await Terra.infer("llama", prompt: text).run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(text)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Model macro auto-detects message as prompt alias")
func modelMacroDetectsMessageAlias() {
  assertMacroExpansion(
    """
    @Traced(model: "llama")
    func generate(message: String) async throws -> String {
      try await doGenerate(message)
    }
    """,
    expandedSource: """
    func generate(message: String) async throws -> String {
      return try await Terra.infer("llama", prompt: message).run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(message)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Model macro auto-detects maxTokens parameter")
func modelMacroDetectsMaxTokens() {
  assertMacroExpansion(
    """
    @Traced(model: "llama")
    func generate(prompt: String, maxTokens: Int) async throws -> String {
      try await doGenerate(prompt, maxTokens: maxTokens)
    }
    """,
    expandedSource: """
    func generate(prompt: String, maxTokens: Int) async throws -> String {
      return try await Terra.infer("llama", prompt: prompt, maxTokens: maxTokens).run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(prompt, maxTokens: maxTokens)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Model macro auto-detects maxOutputTokens parameter")
func modelMacroDetectsMaxOutputTokens() {
  assertMacroExpansion(
    """
    @Traced(model: "llama")
    func generate(prompt: String, maxOutputTokens: Int) async throws -> String {
      try await doGenerate(prompt, maxTokens: maxOutputTokens)
    }
    """,
    expandedSource: """
    func generate(prompt: String, maxOutputTokens: Int) async throws -> String {
      return try await Terra.infer("llama", prompt: prompt, maxTokens: maxOutputTokens).run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(prompt, maxTokens: maxOutputTokens)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Model macro auto-detects temperature parameter")
func modelMacroDetectsTemperature() {
  assertMacroExpansion(
    """
    @Traced(model: "llama")
    func generate(prompt: String, temperature: Double) async throws -> String {
      try await doGenerate(prompt)
    }
    """,
    expandedSource: """
    func generate(prompt: String, temperature: Double) async throws -> String {
      return try await Terra.infer("llama", prompt: prompt, temperature: temperature).run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(prompt)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Model macro with streaming true expands to Terra.stream")
func modelMacroStreamingTrue() {
  assertMacroExpansion(
    """
    @Traced(model: "gpt-4", streaming: true)
    func stream(prompt: String) async throws -> String {
      try await doGenerate(prompt)
    }
    """,
    expandedSource: """
    func stream(prompt: String) async throws -> String {
      return try await Terra.stream("gpt-4", prompt: prompt).run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(prompt)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Agent macro basic expansion")
func agentMacroBasic() {
  assertMacroExpansion(
    """
    @Traced(agent: "ResearchAgent")
    func research(topic: String) async throws -> Report {
      try await doResearch(topic)
    }
    """,
    expandedSource: """
    func research(topic: String) async throws -> Report {
      return try await Terra.agent("ResearchAgent").run { __terraTrace in
        _ = __terraTrace
        try await doResearch(topic)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Agent macro with explicit ID expansion")
func agentMacroWithID() {
  assertMacroExpansion(
    """
    @Traced(agent: "ResearchAgent", id: "agent-1")
    func research(topic: String) async throws -> Report {
      try await doResearch(topic)
    }
    """,
    expandedSource: """
    func research(topic: String) async throws -> Report {
      return try await Terra.agent("ResearchAgent", id: "agent-1").run { __terraTrace in
        _ = __terraTrace
        try await doResearch(topic)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Tool macro basic expansion uses default callId handling")
func toolMacroBasic() {
  assertMacroExpansion(
    """
    @Traced(tool: "search")
    func search(query: String) async throws -> [Result] {
      try await doSearch(query)
    }
    """,
    expandedSource: """
    func search(query: String) async throws -> [Result] {
      return try await Terra.tool("search").run { __terraTrace in
        _ = __terraTrace
        try await doSearch(query)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Tool macro uses function callId parameter when present")
func toolMacroUsesFunctionCallId() {
  assertMacroExpansion(
    """
    @Traced(tool: "search")
    func search(query: String, callId: String) async throws -> [Result] {
      try await doSearch(query)
    }
    """,
    expandedSource: """
    func search(query: String, callId: String) async throws -> [Result] {
      return try await Terra.tool("search", callId: callId).run { __terraTrace in
        _ = __terraTrace
        try await doSearch(query)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Tool macro uses optional callId parameter when present")
func toolMacroUsesOptionalCallId() {
  assertMacroExpansion(
    """
    @Traced(tool: "search")
    func search(query: String, callId: String?) async throws -> [Result] {
      try await doSearch(query)
    }
    """,
    expandedSource: """
    func search(query: String, callId: String?) async throws -> [Result] {
      return try await (callId.map { Terra.tool("search", callId: $0) } ?? Terra.tool("search")).run { __terraTrace in
        _ = __terraTrace
        try await doSearch(query)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Embedding macro basic expansion")
func embeddingMacroBasic() {
  assertMacroExpansion(
    """
    @Traced(embedding: "text-embedding-3-small")
    func embed(input: String) async throws -> [Float] {
      try await doEmbedding(input)
    }
    """,
    expandedSource: """
    func embed(input: String) async throws -> [Float] {
      return try await Terra.embed("text-embedding-3-small").run { __terraTrace in
        _ = __terraTrace
        try await doEmbedding(input)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Embedding macro auto-detects count as inputCount")
func embeddingMacroDetectsCount() {
  assertMacroExpansion(
    """
    @Traced(embedding: "text-embedding-3-small")
    func embed(input: String, count: Int) async throws -> [Float] {
      try await doEmbedding(input)
    }
    """,
    expandedSource: """
    func embed(input: String, count: Int) async throws -> [Float] {
      return try await Terra.embed("text-embedding-3-small", inputCount: count).run { __terraTrace in
        _ = __terraTrace
        try await doEmbedding(input)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Safety macro basic expansion")
func safetyMacroBasic() {
  assertMacroExpansion(
    """
    @Traced(safety: "toxicity")
    func moderate() async throws -> Bool {
      try await doModeration()
    }
    """,
    expandedSource: """
    func moderate() async throws -> Bool {
      return try await Terra.safety("toxicity").run { __terraTrace in
        _ = __terraTrace
        try await doModeration()
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Safety macro auto-detects subject parameter")
func safetyMacroDetectsSubject() {
  assertMacroExpansion(
    """
    @Traced(safety: "toxicity")
    func moderate(subject: String) async throws -> Bool {
      try await doModeration(subject)
    }
    """,
    expandedSource: """
    func moderate(subject: String) async throws -> Bool {
      return try await Terra.safety("toxicity", subject: subject).run { __terraTrace in
        _ = __terraTrace
        try await doModeration(subject)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Model macro uses first prompt-like match when multiple aliases exist")
func modelMacroUsesFirstPromptAlias() {
  assertMacroExpansion(
    """
    @Traced(model: "llama")
    func generate(prompt: String, text: String) async throws -> String {
      try await doGenerate(prompt, text: text)
    }
    """,
    expandedSource: """
    func generate(prompt: String, text: String) async throws -> String {
      return try await Terra.infer("llama", prompt: prompt).run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(prompt, text: text)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Explicit model arg overrides matching function parameter")
func explicitModelArgOverridesFunctionParam() {
  assertMacroExpansion(
    """
    @Traced(model: "gpt-4")
    func generate(model: String, prompt: String) async throws -> String {
      try await doGenerate(model, prompt: prompt)
    }
    """,
    expandedSource: """
    func generate(model: String, prompt: String) async throws -> String {
      return try await Terra.infer("gpt-4", prompt: prompt).run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(model, prompt: prompt)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Explicit macro metadata args override auto-detected parameters")
func explicitMetadataOverridesDetectedParams() {
  assertMacroExpansion(
    """
    @Traced(model: "gpt-4", prompt: "fixed", provider: Terra.ProviderID("openai"), maxOutputTokens: 128, temperature: 0.2)
    func generate(prompt: String, provider: String, maxTokens: Int, temperature: Double) async throws -> String {
      try await doGenerate(prompt)
    }
    """,
    expandedSource: """
    func generate(prompt: String, provider: String, maxTokens: Int, temperature: Double) async throws -> String {
      return try await Terra.infer("gpt-4", prompt: "fixed", provider: Terra.ProviderID("openai"), temperature: 0.2, maxTokens: 128).run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(prompt)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Model macro wraps runtime String parameter into RuntimeID")
func modelMacroWrapsRuntimeStringParameter() {
  assertMacroExpansion(
    """
    @Traced(model: "gpt-4")
    func generate(prompt: String, runtime: String) async throws -> String {
      try await doGenerate(prompt)
    }
    """,
    expandedSource: """
    func generate(prompt: String, runtime: String) async throws -> String {
      return try await Terra.infer("gpt-4", prompt: prompt, runtime: Terra.RuntimeID(runtime)).run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(prompt)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Model macro wraps provider String parameter into ProviderID")
func modelMacroWrapsProviderStringParameter() {
  assertMacroExpansion(
    """
    @Traced(model: "gpt-4")
    func generate(prompt: String, provider: String) async throws -> String {
      try await doGenerate(prompt)
    }
    """,
    expandedSource: """
    func generate(prompt: String, provider: String) async throws -> String {
      return try await Terra.infer("gpt-4", prompt: prompt, provider: Terra.ProviderID(provider)).run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(prompt)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Explicit runtime macro arg overrides detected runtime parameter")
func explicitRuntimeOverridesDetectedParam() {
  assertMacroExpansion(
    """
    @Traced(model: "gpt-4", runtime: Terra.RuntimeID("mlx"))
    func generate(prompt: String, runtime: String) async throws -> String {
      try await doGenerate(prompt)
    }
    """,
    expandedSource: """
    func generate(prompt: String, runtime: String) async throws -> String {
      return try await Terra.infer("gpt-4", prompt: prompt, runtime: Terra.RuntimeID("mlx")).run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(prompt)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Tool macro wraps runtime String parameter into RuntimeID")
func toolMacroWrapsRuntimeStringParameter() {
  assertMacroExpansion(
    """
    @Traced(tool: "search")
    func search(query: String, runtime: String) async throws -> [Result] {
      try await doSearch(query)
    }
    """,
    expandedSource: """
    func search(query: String, runtime: String) async throws -> [Result] {
      return try await Terra.tool("search", runtime: Terra.RuntimeID(runtime)).run { __terraTrace in
        _ = __terraTrace
        try await doSearch(query)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Model macro accepts raw string model without diagnostics")
func modelMacroRawString() {
  assertMacroExpansion(
    """
    @Traced(model: "gpt-4")
    func generate(prompt: String) async throws -> String {
      try await doGenerate(prompt)
    }
    """,
    expandedSource: """
    func generate(prompt: String) async throws -> String {
      return try await Terra.infer("gpt-4", prompt: prompt).run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(prompt)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Model macro rejects runtime streaming expressions")
func modelMacroRejectsRuntimeStreamingExpression() {
  assertMacroExpansion(
    """
    @Traced(model: "gpt-4", streaming: shouldStream)
    func generate(prompt: String, shouldStream: Bool) async throws -> String {
      try await doGenerate(prompt)
    }
    """,
    expandedSource: """
    func generate(prompt: String, shouldStream: Bool) async throws -> String {
      try await doGenerate(prompt)
    }
    """,
    diagnostics: [
      DiagnosticSpec(
        message: "@Traced streaming: must be the literal true or false. Use an explicit Terra.stream/Terra.infer branch for runtime streaming decisions.",
        line: 1,
        column: 1
      )
    ],
    macros: testMacros
  )
}

@Test("Model macro emits fix-it when provider is passed as raw string")
func modelMacroRawProviderDiagnostic() {
  assertMacroExpansion(
    """
    @Traced(model: "gpt-4", provider: "openai")
    func generate(prompt: String) async throws -> String {
      try await doGenerate(prompt)
    }
    """,
    expandedSource: """
    func generate(prompt: String) async throws -> String {
      return try await Terra.infer("gpt-4", prompt: prompt, provider: Terra.ProviderID("openai")).run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(prompt)
      }
    }
    """,
    diagnostics: [
      DiagnosticSpec(
        message: "@Traced provider expects Terra.ProviderID; wrap string literal with Terra.ProviderID(...)",
        line: 1,
        column: 1,
        severity: .warning,
        fixIts: [FixItSpec(message: "wrap with Terra.ProviderID(...)")]
      )
    ],
    macros: testMacros
  )
}

@Test("Model macro emits fix-it when runtime is passed as raw string")
func modelMacroRawRuntimeDiagnostic() {
  assertMacroExpansion(
    """
    @Traced(model: "gpt-4", runtime: "mlx")
    func generate(prompt: String) async throws -> String {
      try await doGenerate(prompt)
    }
    """,
    expandedSource: """
    func generate(prompt: String) async throws -> String {
      return try await Terra.infer("gpt-4", prompt: prompt, runtime: Terra.RuntimeID("mlx")).run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(prompt)
      }
    }
    """,
    diagnostics: [
      DiagnosticSpec(
        message: "@Traced runtime expects Terra.RuntimeID; wrap string literal with Terra.RuntimeID(...)",
        line: 1,
        column: 1,
        severity: .warning,
        fixIts: [FixItSpec(message: "wrap with Terra.RuntimeID(...)")]
      )
    ],
    macros: testMacros
  )
}

@Test("Tool macro accepts raw string callId without diagnostics")
func toolMacroRawCallId() {
  assertMacroExpansion(
    """
    @Traced(tool: "search", callId: "call-1")
    func run(query: String) async throws -> String {
      try await doSearch(query)
    }
    """,
    expandedSource: """
    func run(query: String) async throws -> String {
      return try await Terra.tool("search", callId: "call-1").run { __terraTrace in
        _ = __terraTrace
        try await doSearch(query)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Macro avoids shadowing user trace parameter")
func macroAvoidsShadowingTraceParameter() {
  assertMacroExpansion(
    """
    @Traced(model: "gpt-4")
    func generate(trace: String) async throws -> String {
      try await doGenerate(trace)
    }
    """,
    expandedSource: """
    func generate(trace: String) async throws -> String {
      return try await Terra.infer("gpt-4").run { __terraTrace in
        _ = __terraTrace
        try await doGenerate(trace)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Macro preserves typed throws in generated body")
func macroPreservesTypedThrows() {
  assertMacroExpansion(
    """
    @Traced(model: "gpt-4")
    func generate(prompt: String) async throws(MyError) -> String {
      try await doGenerate(prompt)
    }
    """,
    expandedSource: """
    func generate(prompt: String) async throws(MyError) -> String {
      do {
        return try await Terra.infer("gpt-4", prompt: prompt).run { __terraTrace in
          _ = __terraTrace
          try await doGenerate(prompt)
        }
      } catch {
        throw error as! MyError
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Macro requires async function")
func macroRequiresAsyncFunction() {
  assertMacroExpansion(
    """
    @Traced(model: "llama")
    func generate(prompt: String) throws -> String {
      try doGenerate(prompt)
    }
    """,
    expandedSource: """
    func generate(prompt: String) throws -> String {
      try doGenerate(prompt)
    }
    """,
    diagnostics: [
      DiagnosticSpec(
        message: "@Traced currently supports async functions only because it wraps Terra traced async APIs",
        line: 1,
        column: 1
      )
    ],
    macros: testMacros
  )
}
