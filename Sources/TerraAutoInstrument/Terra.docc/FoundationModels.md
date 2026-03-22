# FoundationModels Integration

Trace Apple Foundation Models with automatic span emission and transcript capture.

## Overview

Terra's FoundationModels integration wraps ``SystemLanguageModel`` sessions with automatic telemetry, capturing generation options, tool calls, and guardrail violations.

## TracedSession Wrapper

``Terra/TracedSession`` provides a drop-in replacement for ``LanguageModelSession``:

```swift
import FoundationModels
import Terra

@available(macOS 26.0, iOS 26.0, *)
func chat() async throws {
  let session = Terra.TracedSession(
    model: .default,
    instructions: "You are a helpful assistant.",
    modelIdentifier: Terra.ModelID("apple/on-device-model")
  )

  let response = try await session.respond(to: "Hello!")
  print(response)
}
```

## Automatic Span Emission

Every call to ``Terra/TracedSession/respond(to:promptCapture:)`` creates an inference span with:

- Model identifier (`gen_ai.request.model`)
- Generation options (temperature, maxTokens)
- Token counts (when available)
- Tool calls and results
- Guardrail violation events

```swift
import FoundationModels
import Terra

@available(macOS 26.0, iOS 26.0, *)
let session = Terra.TracedSession(
  modelIdentifier: Terra.ModelID("apple/foundation-model")
)

// Automatic span with:
// - terra.fm.generation.temperature
// - terra.fm.generation.max_tokens
// - gen_ai.usage.input_tokens
// - gen_ai.usage.output_tokens
let response = try await session.respond(to: "What is Swift?")
```

## Transcript Capture

TracedSession captures tool calls and results from the model's internal transcript:

```swift
import FoundationModels
import Terra

@available(macOS 26.0, iOS 26.0, *)
let session = Terra.TracedSession(modelIdentifier: Terra.ModelID("apple/foundation-model"))

// Tool calls are automatically extracted and attached to spans
let response = try await session.respond(to: "Search for weather in Tokyo")
// If the model calls a tool, these appear on the span:
// - terra.fm.tool.name
// - terra.fm.tool.arguments
// - terra.fm.tool.result
// - terra.fm.tool_call_count
// - terra.fm.tools.called
```

### Content Capture

Control whether prompt and response content is included in spans:

```swift
import FoundationModels
import Terra

@available(macOS 26.0, iOS 26.0, *)
let session = Terra.TracedSession()

// Default: no content capture (respects privacy policy)
let privateResponse = try await session.respond(to: "Sensitive query")

// Include content for debugging (use in development only)
let debugResponse = try await session.respond(
  to: "Query",
  promptCapture: .includeContent  // Captures full prompt/response
)
```

## Streaming Responses

Use ``Terra/TracedSession/streamResponse(to:promptCapture:)`` for streaming with automatic tracing:

```swift
import FoundationModels
import Terra

@available(macOS 26.0, iOS 26.0, *)
let session = Terra.TracedSession()

let stream = session.streamResponse(to: "Write a story about...")

for try await chunk in stream {
  print(chunk, terminator: "")
}
// Streaming spans include:
// - gen_ai.usage.output_tokens (per-chunk when available)
// - terra.fm.stream.first_token (first token event)
```

## Structured Output

``Terra/TracedSession`` supports `@Generable` types for structured responses:

```swift
import FoundationModels
import Terra

@available(macOS 26.0, iOS 26.0, *)
struct WeatherInfo: Generable {
  var city: String
  var temperature: Int
  var condition: String
}

@available(macOS 26.0, iOS 26.0, *)
let session = Terra.TracedSession()

// Response is auto-traced with type information
let weather = try await session.respond(
  to: "What's the weather in San Francisco?",
  generating: WeatherInfo.self
)
// Span includes:
// - terra.foundation_models.response_type = "WeatherInfo"
```

## Guardrail Violations

When a safety guardrail is triggered, Terra automatically emits a separate safety span:

```swift
import FoundationModels
import Terra

@available(macOS 26.0, iOS 26.0, *)
let session = Terra.TracedSession()

do {
  let response = try await session.respond(to: "Prompt that triggers guardrail")
} catch {
  // Guardrail violation creates a span with:
  // - gen_ai.operation.name = "safety"
  // - terra.fm.guardrail.violation_type
  // - terra.auto_instrumented = true
  print("Safety span emitted for violation")
}
```

## Generation Options

Terra captures these generation options from the session:

| Attribute | Description |
|-----------|-------------|
| `gen_ai.request.temperature` | Sampling temperature |
| `gen_ai.request.max_tokens` | Maximum output tokens |
| `terra.fm.generation.sampling_mode` | Sampling mode (when available) |

## Initialization Options

```swift
import FoundationModels
import Terra

@available(macOS 26.0, iOS 26.0, *)
let session = Terra.TracedSession(
  model: .default,                              // Language model
  instructions: "You are a helpful assistant.",  // System instructions
  modelIdentifier: Terra.ModelID("apple/model")  // Custom model ID
)
```

## See Also

- <doc:CoreML-Integration> — CoreML model tracing
- <doc:TerraCore> — Core concepts (privacy, lifecycle)
- <doc:TelemetryEngine-Injection> — Testing with custom engines
