<p align="center">
  <img src="terra-banner.svg" alt="Terra Banner" width="100%" />
</p>

# Terra

Terra is the OpenTelemetry-native observability SDK for on-device GenAI on Apple platforms.
Instrument inference, streaming, agents, tools, embeddings, and safety checks with privacy-safe defaults.

```swift
import Terra

try Terra.start()
let result = try await Terra.inference(model: "gpt-4o-mini", prompt: "Say hello") { "Hello" }
```

[![CI](https://github.com/christopherkarani/Terra/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/christopherkarani/Terra/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%20|%20macOS%20|%20visionOS-red.svg)]()

## Quick Start

```swift
import Terra

try Terra.start()

let answer = try await Terra.inference(model: "gpt-4o-mini", prompt: userPrompt) {
  try await llm.generate(userPrompt)
}
```

## Setup Presets

| Preset | Use when | Start call |
| --- | --- | --- |
| `quickstart` | Local dev defaults | `try Terra.start()` |
| `production` | Persist traces and export in apps | `try Terra.start(.init(preset: .production))` |
| `diagnostics` | Deep troubleshooting with extra telemetry | `try Terra.start(.init(preset: .diagnostics))` |

## Span Types

| Span type | Factory | Example |
| --- | --- | --- |
| Inference | `Terra.inference(model:prompt:)` | `try await Terra.inference(model: "gpt-4o-mini") { "ok" }` |
| Streaming | `Terra.stream(model:prompt:)` | `try await Terra.stream(model: "gpt-4o-mini") { trace in trace.chunk(tokens: 8); return "ok" }` |
| Agent | `Terra.agent(name:id:)` | `try await Terra.agent(name: "planner") { "done" }` |
| Tool | `Terra.tool(name:callID:type:)` | `try await Terra.tool(name: "search", callID: UUID().uuidString) { "result" }` |
| Embedding | `Terra.embedding(model:inputCount:)` | `try await Terra.embedding(model: "text-embedding-3-small", inputCount: 3) { vectors }` |
| Safety check | `Terra.safetyCheck(name:subject:)` | `try await Terra.safetyCheck(name: "toxicity", subject: text) { true }` |

## Privacy Policies

| Policy | Behavior | Use when |
| --- | --- | --- |
| `.redacted` (default) | Captures telemetry metadata with HMAC-SHA256 redaction for content fields | Standard production default |
| `.lengthOnly` | Captures only content lengths (no raw content) | You need shape/size signals only |
| `.capturing` | Allows content capture when opted in per call | Controlled debugging environments |
| `.silent` | Drops content-related telemetry | Strictest privacy mode |

## Macros (`@Traced`)

```swift
import TerraTracedMacro

@Traced(model: "gpt-4o-mini")
func infer(prompt: String) async throws -> String { try await llm.generate(prompt) }

@Traced(model: "gpt-4o-mini", streaming: true)
func stream(prompt: String) async throws -> String { try await llm.generate(prompt) }

@Traced(agent: "planner")
func agentStep() async throws -> String { "ok" }

@Traced(tool: "search")
func runTool(query: String) async throws -> String { "ok" }

@Traced(embedding: "text-embedding-3-small")
func embed(text: String) async throws -> [Float] { [0.1, 0.2] }

@Traced(safety: "toxicity")
func safety(subject: String) async throws -> Bool { true }
```

## Foundation Models

```swift
#if canImport(FoundationModels)
import FoundationModels
import TerraFoundationModels

@available(macOS 26.0, iOS 26.0, *)
func runFoundationModels(prompt: String) async throws -> String {
  // Drop-in traced wrapper around LanguageModelSession
  let session = Terra.TracedSession(model: .default)
  return try await session.respond(to: prompt)
}
#endif
```

## Builder API (Escape Hatch)

Use builders when metadata is dynamic at runtime:

```swift
let result = try await Terra
  .inference(model: modelName, prompt: prompt)
  .provider(providerName)
  .runtime(runtimeName)
  .attribute(.init("app.user_tier"), userTier)
  .includeContent()
  .execute { trace in
    trace.tokens(input: 128, output: 64)
    return try await llm.generate(prompt)
  }
```

## Advanced

- Full integrations: [`Docs/Integrations.md`](Docs/Integrations.md)
- Migration guide: [`Docs/Migration_Guide.md`](Docs/Migration_Guide.md)
- API cookbook: [`Docs/API_Cookbook.md`](Docs/API_Cookbook.md)
- Front-facing API reference: [`Docs/Front_Facing_API.md`](Docs/Front_Facing_API.md)
- Front-facing API examples: [`Docs/Front_Facing_API_Examples.md`](Docs/Front_Facing_API_Examples.md)

## Installation (SwiftPM)

```swift
.package(url: "https://github.com/christopherkarani/Terra.git", from: "0.1.0")
```

Common products:

- `Terra`
- `TerraTracedMacro`
- `TerraFoundationModels`
- `TerraMLX`
- `TerraLlama`

## Requirements

- iOS 13+
- macOS 14+
- visionOS 1+
- tvOS 13+
- watchOS 6+

License: Apache-2.0
