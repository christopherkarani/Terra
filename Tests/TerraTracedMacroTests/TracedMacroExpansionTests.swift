import Testing
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import TerraTracedMacroPlugin

private let testMacros: [String: any Macro.Type] = [
  "Traced": TracedMacro.self,
]

@Test("Model macro expands to Terra.inference(...).execute")
func modelMacroExpansion() {
  assertMacroExpansion(
    """
    @Traced(model: "llama")
    func generate(prompt: String) async throws -> String {
      try await doGenerate(prompt)
    }
    """,
    expandedSource: """
    func generate(prompt: String) async throws -> String {
      return try await Terra.inference(model: "llama", prompt: prompt).execute { trace in
        _ = trace
        try await doGenerate(prompt)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Model macro maps max tokens, provider, and temperature")
func modelMacroAdvancedDetection() {
  assertMacroExpansion(
    """
    @Traced(model: "llama")
    func generate(prompt: String, maxTokens: Int, provider: String, temperature: Double) async throws -> String {
      try await doGenerate(prompt, maxTokens: maxTokens)
    }
    """,
    expandedSource: """
    func generate(prompt: String, maxTokens: Int, provider: String, temperature: Double) async throws -> String {
      return try await Terra.inference(model: "llama", prompt: prompt).maxOutputTokens(maxTokens).temperature(temperature).provider(provider).execute { trace in
        _ = trace
        try await doGenerate(prompt, maxTokens: maxTokens)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Model macro supports explicit streaming mode")
func modelStreamingMacroExpansion() {
  assertMacroExpansion(
    """
    @Traced(model: "gpt-4", streaming: true)
    func stream(prompt: String) async throws -> String {
      try await doGenerate(prompt)
    }
    """,
    expandedSource: """
    func stream(prompt: String) async throws -> String {
      return try await Terra.stream(model: "gpt-4", prompt: prompt).execute { trace in
        _ = trace
        try await doGenerate(prompt)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("@Traced(agent:) expands to Terra.agent(...).execute")
func agentMacroExpansion() {
  assertMacroExpansion(
    """
    @Traced(agent: "ResearchAgent")
    func research(topic: String) async throws -> Report {
      try await doResearch(topic)
    }
    """,
    expandedSource: """
    func research(topic: String) async throws -> Report {
      return try await Terra.agent(name: "ResearchAgent").execute { trace in
        _ = trace
        try await doResearch(topic)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("@Traced(tool:) expands with auto callID")
func toolMacroExpansion() {
  assertMacroExpansion(
    """
    @Traced(tool: "search")
    func search(query: String) async throws -> [Result] {
      try await doSearch(query)
    }
    """,
    expandedSource: """
    func search(query: String) async throws -> [Result] {
      return try await Terra.tool(name: "search", callID: String(UInt64.random(in: 0...UInt64.max), radix: 16)).execute { trace in
        _ = trace
        try await doSearch(query)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("Model macro with stream Bool parameter remains type-checkable")
func modelMacroWithStreamParameterExpansion() {
  assertMacroExpansion(
    """
    @Traced(model: "gpt-4")
    func run(prompt: String, stream: Bool) async throws -> String {
      try await doRun(prompt, stream: stream)
    }
    """,
    expandedSource: """
    func run(prompt: String, stream: Bool) async throws -> String {
      return try await Terra.inference(model: "gpt-4", prompt: prompt).execute { trace in
        _ = trace
        try await doRun(prompt, stream: stream)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("@Traced(embedding:) expands to Terra.embedding(...).execute")
func embeddingMacroExpansion() {
  assertMacroExpansion(
    """
    @Traced(embedding: "text-embedding-3-small")
    func embed(input: String) async throws -> [Float] {
      try await doEmbedding(input)
    }
    """,
    expandedSource: """
    func embed(input: String) async throws -> [Float] {
      return try await Terra.embedding(model: "text-embedding-3-small").execute { trace in
        _ = trace
        try await doEmbedding(input)
      }
    }
    """,
    macros: testMacros
  )
}

@Test("@Traced(safety:) maps subject aliases")
func safetyMacroExpansion() {
  assertMacroExpansion(
    """
    @Traced(safety: "toxicity")
    func moderate(message: String) async throws -> Bool {
      try await doModeration(message)
    }
    """,
    expandedSource: """
    func moderate(message: String) async throws -> Bool {
      return try await Terra.safetyCheck(name: "toxicity", subject: message).execute { trace in
        _ = trace
        try await doModeration(message)
      }
    }
    """,
    macros: testMacros
  )
}
