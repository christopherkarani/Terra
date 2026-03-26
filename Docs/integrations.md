# Integrations

Terra integrates with Apple ML frameworks and popular GenAI backends. This guide covers setup and best practices for each integration.

> **Note:** Use raw string model identifiers and `callId:` strings in new code. `Terra.ModelID` and `Terra.ToolCallID` remain only for compatibility with older call sites.

## Core ML

Capture deterministic runtime facts from CoreML model executions.

### Automatic Span Emission

Terra automatically instruments CoreML via method swizzling when enabled:

```swift
import CoreML
import Terra

try await Terra.start(.init(preset: .production))

// Auto-instrumented — spans created automatically
let model = try MLModel(contentsOf: modelURL)
let prediction = try model.prediction(from: inputProvider)

// Spans include:
// - gen_ai.operation.name = "inference"
// - gen_ai.request.model = model identifier
// - gen_ai.provider.name = "on_device"
// - terra.runtime = "coreml"
// - terra.auto_instrumented = true
// - terra.coreml.compute_units = selected compute units
```

### MLModelConfiguration

Configure compute units for your workload:

```swift
import CoreML

let config = MLModelConfiguration()

// CPU + GPU (default, balanced)
config.computeUnits = .cpuAndGPU

// All accelerators including Neural Engine
config.computeUnits = .all

// Debugging: CPU only
config.computeUnits = .cpuOnly

// GPU only
config.computeUnits = .gpuOnly
```

### Manual Attribution

Attach model-specific metadata using Terra's canonical API:

```swift
import CoreML
import Terra

try await Terra.start(.init(preset: .quickstart))

let result = try await Terra
  .infer(
    "coreml/com.yourorg.StableDiffusion@v2",
    runtime: Terra.RuntimeID("coreml"),
    provider: Terra.ProviderID("coreml")
  )
  .run { trace in
    trace.tag("terra.coreml.compute_units", "all")
    // Note: Custom attributes can use any key namespace
    // trace.tag("custom.model_version", "2.1")
    let config = MLModelConfiguration()
    config.computeUnits = .all
    let model = try MLModel(contentsOf: modelURL, configuration: config)
    let prediction = try model.prediction(from: inputProvider)
    return prediction
  }
```

### Excluding Models

Exclude low-latency models from tracing overhead:

```swift
// When using Terra.start() with feature flags, CoreML instrumentation
// is controlled via Configuration.Features.coreML

// For fine-grained exclusion, use CoreMLInstrumentation directly:
CoreMLInstrumentation.install(.init(
  enabled: true,
  excludedModels: ["low-latency-model-id", "streaming-model-id"]
))
```

## MLX (Apple Silicon ML)

Track MLX model executions with bounded metadata:

```swift
import MLX
import Terra
import TerraMLX

try await Terra.start(.init(preset: .quickstart))

// Use TerraMLX.traced() for proper MLX integration
let result = try await TerraMLX.traced(
  model: "mlx/local/llama-3.2-1b",
  device: "gpu"
) {
  // MLX inference here
  let output = try await mlxModel.generate(prompt: "Hello")
  return output
}
```

> **Note:** The `TerraMLX.traced()` API automatically sets provider to "mlx" and tracks device correctly.
> Available MLX attribute keys: `terra.mlx.device`, `terra.mlx.memory_footprint_mb`, `terra.mlx.model_load_duration_ms`

### Device Selection

```swift
// Device types for terra.mlx.device:
// - "cpu" — CPU only
// - "gpu" — Apple GPU (unified memory)
// - "ane" — Apple Neural Engine (int8 quantization)
```

### Quantization Labels

```swift
// Quantization types for terra.mlx.quantization:
// - "fp32" — Full precision
// - "fp16" — Half precision
// - "q8" — 8-bit quantization
// - "q4" — 4-bit quantization (most compressed)
```

## FoundationModels (Apple On-Device AI)

Trace Foundation Models sessions with automatic transcript capture:

```swift
import FoundationModels
import Terra

try await Terra.start(.init(preset: .quickstart))

@available(macOS 26.0, iOS 26.0, *)
func chat() async throws {
  let session = Terra.TracedSession(
    model: .default,
    instructions: "You are a helpful assistant.",
    modelIdentifier: "apple/on-device-model"
  )

  // Automatic span with generation options, tool calls, guardrail events
  let response = try await session.respond(to: "Hello!")
  print(response)
}
```

### Streaming Responses

```swift
@available(macOS 26.0, iOS 26.0, *)
func streamChat() async throws {
  let session = Terra.TracedSession()

  let stream = session.streamResponse(to: "Write a story...")

  for try await chunk in stream {
    print(chunk, terminator: "")
  }
}
```

### Structured Output with Generable

```swift
@available(macOS 26.0, iOS 26.0, *)
struct WeatherInfo: Generable {
  var city: String
  var temperature: Int
  var condition: String
}

@available(macOS 26.0, iOS 26.0, *)
func structuredOutput() async throws {
  let session = Terra.TracedSession()

  let weather = try await session.respond(
    to: "What's the weather in San Francisco?",
    generating: WeatherInfo.self
  )
  // weather.city, weather.temperature, weather.condition
}
```

### Content Capture Control

```swift
@available(macOS 26.0, iOS 26.0, *)
func contentCapture() async throws {
  let session = Terra.TracedSession()

  // Default: no content captured (respects privacy policy)
  let privateResponse = try await session.respond(to: "Sensitive query")

  // Development: include full prompt/response
  let debugResponse = try await session.respond(
    to: "Query with debug",
    promptCapture: .includeContent
  )
}
```

## Privacy and Cardinality Rules

**Critical**: Follow these rules to prevent sensitive data leaks and cardinality explosions:

### Do

- Attach counts and latencies as numeric attributes
- Use bounded string labels for model/device/runtime identifiers
- Capture content only with explicit `.capture(.includeContent)` and only in development
- Use ``Terra/PrivacyPolicy`` to control default behavior

### Don't

- Attach raw prompts or tool arguments as attributes
- Attach model outputs as attributes
- Use unbounded array attributes
- Capture content in production

### Example: Proper Attribution

```swift
// GOOD: Bounded labels, numeric metrics via trace handle
Terra
  .infer(modelID, prompt: "...")
  .run { trace in
    trace.tokens(input: 150, output: 42)
    trace.responseModel("gpt-4o")
    // ...
  }

// Note: Use trace.tag() for string attributes. For numeric metrics,
// use trace.tokens(input:output:) and trace.responseModel(_:) instead.
```

## HTTP AI API Auto-Instrumentation

Terra automatically instruments HTTP requests to known AI API endpoints:

```swift
import Terra

// HTTP auto-instrumentation is enabled by default
try await Terra.start(.init(preset: .quickstart))

// Requests to monitored hosts are automatically traced
let client = OpenAIClient(apiKey: "...")  // OpenAI, Anthropic, etc.
let response = try await client.chat.create(model: "gpt-4o", messages: [...])

// Spans include:
// - http.method, http.url, http.status_code
// - gen_ai.operation.name, gen_ai.request.model
// - gen_ai.usage.input_tokens, gen_ai.usage.output_tokens
```

Configure monitored hosts explicitly:

```swift
var config = Terra.Configuration(preset: .quickstart)
config.features = [.http]

// Custom hosts are monitored alongside defaults
try await Terra.start(config)
```

## See Also

- <doc:TerraCore> — Privacy, lifecycle, configuration
- <doc:CoreML-Integration> — CoreML integration details
- <doc:FoundationModels> — FoundationModels integration details
- <doc:API-Reference> — Complete API reference
