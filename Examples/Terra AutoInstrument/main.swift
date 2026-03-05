/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

/// Terra Auto-Instrumentation Example
///
/// This example demonstrates the three tiers of Terra auto-instrumentation:
///
/// 1. `Terra.start()` — Zero-code CoreML + HTTP AI API tracing
/// 2. `@Traced(model:)` — One annotation on any async function
/// 3. `TerraMLX.traced(model:)` — One closure for MLX generation
///
/// To use in your own project, add the appropriate Terra module to your
/// Package.swift dependencies.

import Foundation
import Terra

@main
struct TerraAutoInstrumentExample {
  static func main() async throws {
// ──────────────────────────────────────────────
// Tier 1: Zero-Code Auto-Instrumentation
// ──────────────────────────────────────────────

    // One line. Every CoreML prediction and HTTP AI API call is now traced.
    try await Terra.start()

    // Configure with presets:
    // try await Terra.start(.init(preset: .production))
    //
    // Or customize:
    // var config = Terra.Configuration()
    // config.enableLogs = true
    // config.profiling.enableMemoryProfiler = true
    // try await Terra.start(config)

// ──────────────────────────────────────────────
// Tier 2: @Traced Annotation (import TerraTracedMacro)
// ──────────────────────────────────────────────

// @Traced(model: Terra.ModelID("llama-3.2-1B"))
// func summarize(prompt: String, maxTokens: Int = 512) async throws -> String {
//   try await mlxContainer.generate(prompt: prompt, maxTokens: maxTokens)
// }
// The macro auto-detects `prompt` and `maxTokens` parameters and wraps
// the function body in Terra.infer(...).run { ... }.

// ──────────────────────────────────────────────
// Tier 3: TerraMLX Closure (import TerraMLX)
// ──────────────────────────────────────────────

// let result = try await TerraMLX.traced(model: Terra.ModelID("mlx-community/Llama-3.2-1B")) {
//   try await container.perform { context in
//     var firstToken = true
//     let output = try MLXLMCommon.generate(
//       input: context.processor.prepare(input: .init(prompt: "Hello")),
//       parameters: GenerateParameters(temperature: 0.7),
//       context: context
//     ) { tokens in
//       if firstToken { TerraMLX.recordFirstToken(); firstToken = false }
//       return .more
//     }
//     return context.tokenizer.decode(tokens: output.tokens)
//   }
// }

// ──────────────────────────────────────────────
// Foundation Models (import TerraFoundationModels, macOS 26+)
// ──────────────────────────────────────────────

// let session = Terra.TracedSession()
// let response = try await session.respond(to: "What is Swift?")
// // ^ Automatically creates a gen_ai.inference span

print("Terra auto-instrumentation is active.")
print("CoreML predictions and HTTP AI API calls will produce OpenTelemetry spans.")
  }
}
