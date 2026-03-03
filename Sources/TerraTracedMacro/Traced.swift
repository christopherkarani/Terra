/// Wraps the function body in a traced Terra operation using `.execute { ... }`.
///
/// The macro auto-detects common parameter names:
/// - prompt aliases: `prompt`/`input`/`query`/`text`/`message`/`subject`
/// - max token aliases: `maxTokens`/`maxOutputTokens`/`max_tokens`
/// - optional metadata: `temperature`/`provider`/`stream`
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

@attached(body)
public macro Traced(model: String, streaming: Bool) = #externalMacro(module: "TerraTracedMacroPlugin", type: "TracedMacro")

@attached(body)
public macro Traced(agent: String, id: String? = nil) = #externalMacro(module: "TerraTracedMacroPlugin", type: "TracedMacro")

@attached(body)
public macro Traced(tool: String, type: String? = nil) = #externalMacro(module: "TerraTracedMacroPlugin", type: "TracedMacro")

@attached(body)
public macro Traced(embedding: String) = #externalMacro(module: "TerraTracedMacroPlugin", type: "TracedMacro")

@attached(body)
public macro Traced(safety: String) = #externalMacro(module: "TerraTracedMacroPlugin", type: "TracedMacro")
