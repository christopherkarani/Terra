/// Wraps the function body in a `Terra.withInferenceSpan` call.
///
/// The macro auto-detects parameters named `prompt`/`input`/`query`/`text` (for prompt capture)
/// and `maxTokens`/`maxOutputTokens`/`max_tokens` (for max output tokens).
///
/// Usage:
/// ```swift
/// @Traced(model: "llama-3.2-1B")
/// func generate(prompt: String, maxTokens: Int = 512) async throws -> String {
///   try await container.generate(prompt: prompt, maxTokens: maxTokens)
/// }
/// ```
@attached(body)
public macro Traced(model: String) = #externalMacro(module: "TerraTracedMacroPlugin", type: "TracedMacro")
