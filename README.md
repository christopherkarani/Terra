<p align="center">
  <img src="terra-banner.svg" alt="Terra Banner" width="100%" />
</p>

# Terra

Terra is an OpenTelemetry-native observability SDK for on-device GenAI on Apple platforms.
Instrument inference, streaming, agents, tools, embeddings, and safety checks with privacy-safe defaults.

```swift
import Terra

try Terra.start()
let result = try await Terra.infer("gpt-4o-mini", prompt: "Say hello").run { "Hello" }
```

[![CI](https://github.com/christopherkarani/Terra/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/christopherkarani/Terra/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%20|%20macOS%20|%20visionOS-red.svg)]()

## Quick Start

```swift
import Terra

try Terra.start()

let answer = try await Terra
  .infer("gpt-4o-mini", prompt: userPrompt, provider: "openai", runtime: "http_api")
  .run { trace in
    trace.event("request.start")
    trace.tokens(input: 120, output: 70)
    return try await llm.generate(userPrompt)
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
| Inference | `Terra.infer(_:prompt:provider:runtime:temperature:maxTokens:)` | `try await Terra.infer("gpt-4o-mini", prompt: prompt).run { "ok" }` |
| Streaming | `Terra.stream(_:prompt:provider:runtime:temperature:maxTokens:expectedTokens:)` | `try await Terra.stream("gpt-4o-mini").run { trace in trace.chunk(tokens: 8); return "ok" }` |
| Agent | `Terra.agent(_:id:provider:runtime:)` | `try await Terra.agent("planner").run { "done" }` |
| Tool | `Terra.tool(_:callID:type:provider:runtime:)` | `try await Terra.tool("search", callID: UUID().uuidString).run { "result" }` |
| Embedding | `Terra.embed(_:inputCount:provider:runtime:)` | `try await Terra.embed("text-embedding-3-small", inputCount: 3).run { vectors }` |
| Safety check | `Terra.safety(_:subject:provider:runtime:)` | `try await Terra.safety("toxicity", subject: text).run { true }` |

## Privacy Policies

| Policy | Behavior | Use when |
| --- | --- | --- |
| `.redacted` (default) | Captures telemetry metadata with HMAC-SHA256 redaction for content fields | Standard production default |
| `.lengthOnly` | Captures only content lengths (no raw content) | You need shape/size signals only |
| `.capturing` | Allows content capture when opted in per call | Controlled debugging environments |
| `.silent` | Drops content-related telemetry | Strictest privacy mode |

## Composable Call API

Use call composition when metadata is dynamic at runtime:

```swift
let result = try await Terra
  .infer(modelName, prompt: prompt, provider: providerName, runtime: runtimeName)
  .capture(.includeContent)
  .attr(.init("app.user_tier"), userTier)
  .attr(.init("app.retry"), false)
  .run { trace in
    trace.responseModel(modelName)
    trace.tokens(input: 128, output: 64)
    return try await llm.generate(prompt)
  }
```

## Configuration Persistence

```swift
var config = Terra.Configuration(preset: .production)
config.persistence = .defaults()
try Terra.start(config)
```

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
  let session = Terra.TracedSession(model: .default)
  return try await session.respond(to: prompt)
}
#endif
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
