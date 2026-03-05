/// Wraps the function body in a traced Terra operation using `.run { ... }`.
///
/// The macro supports explicit metadata arguments and auto-detects common parameter names:
/// - prompt aliases: `prompt`/`input`/`query`/`text`/`message`/`subject`
/// - max token aliases: `maxTokens`/`maxOutputTokens`/`max_tokens`
/// - optional metadata: `temperature`/`provider`/`stream`
///
/// Usage:
/// ```swift
/// @Traced(model: "llama-3.2-1B", provider: "mlx")
/// func generate(prompt: String, maxTokens: Int = 512) async throws -> String {
///   try await container.generate(prompt: prompt, maxTokens: maxTokens)
/// }
/// ```
@attached(body)
public macro Traced(
  model: String,
  prompt: String? = nil,
  provider: String? = nil,
  temperature: Double? = nil,
  maxTokens: Int? = nil,
  maxOutputTokens: Int? = nil,
  streaming: Bool = false
) = #externalMacro(module: "TerraTracedMacroPlugin", type: "TracedMacro")

@attached(body)
public macro Traced(agent: String, id: String? = nil) = #externalMacro(module: "TerraTracedMacroPlugin", type: "TracedMacro")

@attached(body)
public macro Traced(tool: String, callID: String? = nil, type: String? = nil) = #externalMacro(module: "TerraTracedMacroPlugin", type: "TracedMacro")

@attached(body)
public macro Traced(embedding: String, count: Int? = nil, inputCount: Int? = nil) = #externalMacro(module: "TerraTracedMacroPlugin", type: "TracedMacro")

@attached(body)
public macro Traced(safety: String, subject: String? = nil) = #externalMacro(module: "TerraTracedMacroPlugin", type: "TracedMacro")
