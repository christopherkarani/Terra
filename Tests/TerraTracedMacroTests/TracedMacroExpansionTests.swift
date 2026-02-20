import Testing
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import TerraTracedMacroPlugin

// The macro under test
private let testMacros: [String: any Macro.Type] = [
  "Traced": TracedMacro.self,
]

// MARK: - Basic expansion with prompt parameter

@Test("Macro expands function with prompt parameter into withInferenceSpan")
func basicExpansionWithPromptParam() {
  assertMacroExpansion(
    """
    @Traced(model: "llama")
    func generate(prompt: String) async throws -> String {
      try await doGenerate(prompt)
    }
    """,
    expandedSource: """
    func generate(prompt: String) async throws -> String {
      return try await Terra.withInferenceSpan(
        .init(model: "llama", prompt: prompt)
      ) { scope in
        try await doGenerate(prompt)
      }
    }
    """,
    macros: testMacros
  )
}

// MARK: - maxTokens parameter captured

@Test("Macro captures maxTokens parameter as maxOutputTokens in InferenceRequest")
func expansionWithMaxTokensParam() {
  assertMacroExpansion(
    """
    @Traced(model: "llama")
    func generate(prompt: String, maxTokens: Int) async throws -> String {
      try await doGenerate(prompt, maxTokens: maxTokens)
    }
    """,
    expandedSource: """
    func generate(prompt: String, maxTokens: Int) async throws -> String {
      return try await Terra.withInferenceSpan(
        .init(model: "llama", prompt: prompt, maxOutputTokens: maxTokens)
      ) { scope in
        try await doGenerate(prompt, maxTokens: maxTokens)
      }
    }
    """,
    macros: testMacros
  )
}

// MARK: - No matching parameters: only model in InferenceRequest

@Test("Macro with no matching parameters only puts model in InferenceRequest")
func expansionWithNoMatchingParameters() {
  assertMacroExpansion(
    """
    @Traced(model: "llama")
    func generate(config: String) async throws -> String {
      try await doGenerate(config)
    }
    """,
    expandedSource: """
    func generate(config: String) async throws -> String {
      return try await Terra.withInferenceSpan(
        .init(model: "llama")
      ) { scope in
        try await doGenerate(config)
      }
    }
    """,
    macros: testMacros
  )
}

// MARK: - async throws produces try await

@Test("Macro wraps async throws function body with try await")
func asyncThrowsFunctionUsesTryAwait() {
  assertMacroExpansion(
    """
    @Traced(model: "gpt-4")
    func run() async throws -> String {
      try await doWork()
    }
    """,
    expandedSource: """
    func run() async throws -> String {
      return try await Terra.withInferenceSpan(
        .init(model: "gpt-4")
      ) { scope in
        try await doWork()
      }
    }
    """,
    macros: testMacros
  )
}

// MARK: - input: String alternative prompt name is captured

@Test("Macro captures 'input' parameter as prompt in InferenceRequest")
func expansionWithInputParamName() {
  assertMacroExpansion(
    """
    @Traced(model: "llama")
    func generate(input: String) async throws -> String {
      try await doGenerate(input)
    }
    """,
    expandedSource: """
    func generate(input: String) async throws -> String {
      return try await Terra.withInferenceSpan(
        .init(model: "llama", prompt: input)
      ) { scope in
        try await doGenerate(input)
      }
    }
    """,
    macros: testMacros
  )
}

// MARK: - maxOutputTokens param name is captured

@Test("Macro captures 'maxOutputTokens' parameter name correctly")
func expansionWithMaxOutputTokensParamName() {
  assertMacroExpansion(
    """
    @Traced(model: "llama")
    func generate(prompt: String, maxOutputTokens: Int) async throws -> String {
      try await doGenerate(prompt, tokens: maxOutputTokens)
    }
    """,
    expandedSource: """
    func generate(prompt: String, maxOutputTokens: Int) async throws -> String {
      return try await Terra.withInferenceSpan(
        .init(model: "llama", prompt: prompt, maxOutputTokens: maxOutputTokens)
      ) { scope in
        try await doGenerate(prompt, tokens: maxOutputTokens)
      }
    }
    """,
    macros: testMacros
  )
}

// MARK: - Error diagnostics

@Test("Macro throws diagnostic when model argument label is missing from call")
func missingModelArgumentProducesDiagnostic() {
  assertMacroExpansion(
    """
    @Traced(model: "")
    func generate(prompt: String) async throws -> String {
      try await doGenerate(prompt)
    }
    """,
    expandedSource: """
    func generate(prompt: String) async throws -> String {
      return try await Terra.withInferenceSpan(
        .init(model: "", prompt: prompt)
      ) { scope in
        try await doGenerate(prompt)
      }
    }
    """,
    macros: testMacros
  )
}
