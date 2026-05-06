# Terra SDK API Reference

## Table of Contents
- [Span Methods](#span-methods)
- [Request Types](#request-types)
- [Scope Types](#scope-types)
- [Privacy Types](#privacy-types)
- [Auto-Instrumentation](#auto-instrumentation)
- [Attribute Keys & Span Names](#attribute-keys--span-names)
- [Framework Wrappers](#framework-wrappers)

---

## Span Methods

All span methods are `async` and propagate the parent context automatically.

### `withInferenceSpan`
```swift
@discardableResult
public static func withInferenceSpan<R>(
  _ request: InferenceRequest,
  _ body: @Sendable (Scope<InferenceSpan>) async throws -> R
) async rethrows -> R
```
Use for non-streaming LLM calls. The scope provides `addEvent`, `setAttributes`, `recordError`, and `span` escape hatch.

### `withStreamingInferenceSpan`
```swift
@discardableResult
public static func withStreamingInferenceSpan<R>(
  _ request: InferenceRequest,
  _ body: @Sendable (StreamingInferenceScope) async throws -> R
) async rethrows -> R
```
Use for streaming LLM calls. Automatically sets `request.stream = true` if not already set. The `StreamingInferenceScope` provides streaming-specific methods plus all base scope methods.

### `withAgentInvocationSpan`
```swift
@discardableResult
public static func withAgentInvocationSpan<R>(
  agent: Agent,
  _ body: @Sendable (Scope<AgentInvocationSpan>) async throws -> R
) async rethrows -> R
```
Use for agent orchestration loops. Nest child spans (inference, tool, embedding) inside the body.

### `withToolExecutionSpan`
```swift
@discardableResult
public static func withToolExecutionSpan<R>(
  tool: Tool,
  call: ToolCall,
  _ body: @Sendable (Scope<ToolExecutionSpan>) async throws -> R
) async rethrows -> R
```
Use for individual tool/function call executions.

### `withEmbeddingSpan`
```swift
@discardableResult
public static func withEmbeddingSpan<R>(
  _ request: EmbeddingRequest,
  _ body: @Sendable (Scope<EmbeddingSpan>) async throws -> R
) async rethrows -> R
```
Use for embedding generation calls.

### `withSafetyCheckSpan`
```swift
@discardableResult
public static func withSafetyCheckSpan<R>(
  _ check: SafetyCheck,
  _ body: @Sendable (Scope<SafetyCheckSpan>) async throws -> R
) async rethrows -> R
```
Use for content moderation and safety checks.

---

## Request Types

All defined in `Sources/Terra/Terra+Requests.swift`.

### `InferenceRequest`
```swift
public struct InferenceRequest: Sendable, Hashable {
  public var model: String
  public var prompt: String?
  public var promptCapture: CaptureIntent  // default: .default
  public var maxOutputTokens: Int?
  public var temperature: Double?
  public var stream: Bool?

  public init(
    model: String,
    prompt: String? = nil,
    promptCapture: CaptureIntent = .default,
    maxOutputTokens: Int? = nil,
    temperature: Double? = nil,
    stream: Bool? = nil
  )
}
```

### `EmbeddingRequest`
```swift
public struct EmbeddingRequest: Sendable, Hashable {
  public var model: String
  public var inputCount: Int?

  public init(model: String, inputCount: Int? = nil)
}
```

### `Agent`
```swift
public struct Agent: Sendable, Hashable {
  public var name: String
  public var id: String?

  public init(name: String, id: String? = nil)
}
```

### `Tool`
```swift
public struct Tool: Sendable, Hashable {
  public var name: String
  public var type: String?

  public init(name: String, type: String? = nil)
}
```

### `ToolCall`
```swift
public struct ToolCall: Sendable, Hashable {
  public var id: String

  public init(id: String)
}
```

### `SafetyCheck`
```swift
public struct SafetyCheck: Sendable, Hashable {
  public var name: String
  public var subject: String?
  public var subjectCapture: CaptureIntent  // default: .default

  public init(
    name: String,
    subject: String? = nil,
    subjectCapture: CaptureIntent = .default
  )
}
```

---

## Scope Types

### `Scope<Kind>`
```swift
public final class Scope<Kind>: @unchecked Sendable {
  /// Advanced escape hatch for OTel integrations.
  public var span: any Span { get }

  public func addEvent(_ name: String, attributes: [String: AttributeValue] = [:])
  public func recordError(_ error: any Error, captureMessage: Bool = true)
  public func setAttributes(_ attributes: [String: AttributeValue])
}
```

Kind markers (empty enums for compile-time safety):
- `Terra.InferenceSpan`
- `Terra.EmbeddingSpan`
- `Terra.AgentInvocationSpan`
- `Terra.ToolExecutionSpan`
- `Terra.SafetyCheckSpan`

### `StreamingInferenceScope`
```swift
public final class StreamingInferenceScope: @unchecked Sendable {
  /// The underlying OTel span.
  public var span: any Span { get }

  /// Add a named event to the span.
  public func addEvent(_ name: String, attributes: [String: AttributeValue] = [:])

  /// Set attributes on the span.
  public func setAttributes(_ attributes: [String: AttributeValue])

  /// Record token generation (incremental). First call sets TTFT.
  public func recordToken(_ count: Int = 1)

  /// Record total output token count (absolute). First call sets TTFT.
  public func recordOutputTokenCount(_ totalCount: Int)

  /// Record a streaming chunk arrival. First call sets TTFT.
  public func recordChunk()
}
```

Computed attributes on `finish()`:
- `terra.stream.time_to_first_token_ms` — TTFT in milliseconds
- `terra.stream.tokens_per_second` — derived from token count and generation duration
- `terra.stream.output_tokens` — total output token count
- `terra.stream.chunk_count` — total chunk count

---

## Privacy Types

All defined in `Sources/Terra/Terra+Privacy.swift`.

### `ContentPolicy`
```swift
public enum ContentPolicy: Sendable, Hashable {
  case never    // Default. Never capture prompt/output content.
  case optIn    // Only capture when CaptureIntent is .optIn.
  case always   // Always capture content.
}
```

### `CaptureIntent`
```swift
public enum CaptureIntent: Sendable, Hashable {
  case `default`  // Follow ContentPolicy.
  case optIn      // Explicitly opt in to capture (requires .optIn or .always policy).
}
```

### `RedactionStrategy`
```swift
public enum RedactionStrategy: Sendable, Hashable {
  case drop              // Drop content entirely
  case lengthOnly        // Only record character length
  case hashHMACSHA256    // Default. Keyed HMAC-SHA256 digest + length
  case hashSHA256        // Legacy deterministic SHA256
}
```

### `Privacy`
```swift
public struct Privacy: Sendable, Hashable {
  public var contentPolicy: ContentPolicy       // default: .never
  public var redaction: RedactionStrategy        // default: .hashHMACSHA256
  public var anonymizationKey: Data?             // default: nil
  public var emitLegacySHA256Attributes: Bool    // default: false

  public init(
    contentPolicy: ContentPolicy = .never,
    redaction: RedactionStrategy = .hashHMACSHA256,
    anonymizationKey: Data? = nil,
    emitLegacySHA256Attributes: Bool = false
  )

  public static let `default` = Privacy()
}
```

---

## Auto-Instrumentation

Defined in `Sources/TerraAutoInstrument/Terra+Start.swift`.

### `Terra.start()`
```swift
public static func start(_ config: AutoInstrumentConfiguration = .init()) throws
```
One-line setup. Configures OpenTelemetry, installs Terra runtime, enables CoreML + HTTP auto-instrumentation. **Must be called before any URLSession or CoreML calls.**

### `AutoInstrumentConfiguration`
```swift
public struct AutoInstrumentConfiguration: Sendable {
  public var privacy: Privacy                           // default: .default
  public var openTelemetry: OpenTelemetryConfiguration  // default: .init()
  public var instrumentations: Instrumentations         // default: .all
  public var openClaw: OpenClawConfiguration            // default: .disabled
  public var proxy: ProxyConfiguration?                 // default: nil
  public var aiAPIHosts: Set<String>                    // default: HTTPAIInstrumentation.defaultAIHosts
  public var excludedCoreMLModels: Set<String>          // default: []
  public var profiling: Profiling                       // default: .init()
}
```

### `Instrumentations` (OptionSet)
```swift
public struct Instrumentations: OptionSet, Sendable {
  public static let coreML              // Auto-instrument MLModel.prediction(from:)
  public static let httpAIAPIs          // Auto-instrument HTTP to known AI hosts
  public static let proxy               // Reserved for proxy instrumentation
  public static let openClawGateway     // Auto-instrument OpenClaw gateway requests
  public static let openClawDiagnostics // OpenClaw diagnostics mode

  public static let all: Instrumentations = [.coreML, .httpAIAPIs]
  public static let none = Instrumentations([])
}
```

### `Profiling`
```swift
public struct Profiling: Sendable {
  public var enableMemoryProfiler: Bool  // default: false
  public var enableMetalProfiler: Bool   // default: false
}
```

### `OpenTelemetryConfiguration`
```swift
public struct OpenTelemetryConfiguration: Equatable {
  public var tracerProviderStrategy: TracerProviderStrategy  // default: .registerNew
  public var enableTraces: Bool        // default: true
  public var enableMetrics: Bool       // default: true
  public var enableLogs: Bool          // default: false
  public var enableSignposts: Bool     // default: true
  public var enableSessions: Bool      // default: true
  public var otlpTracesEndpoint: URL   // default: http://localhost:4318/v1/traces
  public var otlpMetricsEndpoint: URL  // default: http://localhost:4318/v1/metrics
  public var otlpLogsEndpoint: URL     // default: http://localhost:4318/v1/logs
  public var metricsExportInterval: TimeInterval  // default: 60
  public var persistence: PersistenceConfiguration?
  public var serviceName: String?
  public var serviceVersion: String?
  public var resourceAttributes: [String: AttributeValue]
  public var traceSamplingRatio: Double?
}
```

### Default AI Hosts (auto-instrumented HTTP)
```swift
HTTPAIInstrumentation.defaultAIHosts = [
  "api.openai.com",
  "api.anthropic.com",
  "generativelanguage.googleapis.com",
  "api.together.xyz",
  "api.mistral.ai",
  "api.groq.com",
  "api.cohere.com",
  "api.fireworks.ai",
]
```

---

## Attribute Keys & Span Names

Defined in `Sources/Terra/Terra+Constants.swift`.

### Span Names
| Constant | Value |
|----------|-------|
| `SpanNames.inference` | `"gen_ai.inference"` |
| `SpanNames.embedding` | `"gen_ai.embeddings"` |
| `SpanNames.agentInvocation` | `"gen_ai.agent"` |
| `SpanNames.toolExecution` | `"gen_ai.tool"` |
| `SpanNames.safetyCheck` | `"terra.safety_check"` |

### GenAI Attribute Keys (`Keys.GenAI.*`)
| Key | Attribute String |
|-----|-----------------|
| `operationName` | `gen_ai.operation.name` |
| `requestModel` | `gen_ai.request.model` |
| `requestMaxTokens` | `gen_ai.request.max_tokens` |
| `requestTemperature` | `gen_ai.request.temperature` |
| `requestStream` | `gen_ai.request.stream` |
| `usageInputTokens` | `gen_ai.usage.input_tokens` |
| `usageOutputTokens` | `gen_ai.usage.output_tokens` |
| `responseModel` | `gen_ai.response.model` |
| `providerName` | `gen_ai.provider.name` |
| `agentName` | `gen_ai.agent.name` |
| `agentID` | `gen_ai.agent.id` |
| `toolName` | `gen_ai.tool.name` |
| `toolType` | `gen_ai.tool.type` |
| `toolCallID` | `gen_ai.tool.call.id` |

### Terra Attribute Keys (`Keys.Terra.*`)
| Key | Attribute String |
|-----|-----------------|
| `contentPolicy` | `terra.privacy.content_policy` |
| `contentRedaction` | `terra.privacy.content_redaction` |
| `promptLength` | `terra.prompt.length` |
| `promptHMACSHA256` | `terra.prompt.hmac_sha256` |
| `promptSHA256` | `terra.prompt.sha256` |
| `embeddingInputCount` | `terra.embeddings.input.count` |
| `safetyCheckName` | `terra.safety.check.name` |
| `safetySubjectLength` | `terra.safety.subject.length` |
| `safetySubjectHMACSHA256` | `terra.safety.subject.hmac_sha256` |
| `anonymizationKeyID` | `terra.anonymization.key_id` |
| `autoInstrumented` | `terra.auto_instrumented` |
| `runtime` | `terra.runtime` |
| `streamTimeToFirstTokenMs` | `terra.stream.time_to_first_token_ms` |
| `streamTokensPerSecond` | `terra.stream.tokens_per_second` |
| `streamOutputTokens` | `terra.stream.output_tokens` |
| `streamChunkCount` | `terra.stream.chunk_count` |
| `streamFirstTokenEvent` | `terra.first_token` |
| `thermalState` | `terra.process.thermal_state` |
| `processMemoryResidentDeltaMB` | `process.memory.resident_delta_mb` |
| `processMemoryPeakMB` | `process.memory.peak_mb` |

### Metric Names
| Constant | Value |
|----------|-------|
| `MetricNames.inferenceCount` | `terra.inference.count` |
| `MetricNames.inferenceDurationMs` | `terra.inference.duration_ms` |

### Operation Names
| Case | Raw Value |
|------|-----------|
| `.inference` | `"inference"` |
| `.chat` | `"chat"` |
| `.textCompletion` | `"text_completion"` |
| `.embeddings` | `"embeddings"` |
| `.invokeAgent` | `"invoke_agent"` |
| `.executeTool` | `"execute_tool"` |
| `.safetyCheck` | `"safety_check"` |

---

## Framework Wrappers

### TerraFoundationModels — `TerraTracedSession`
```swift
@available(macOS 26.0, iOS 26.0, *)
public final class TerraTracedSession: @unchecked Sendable {
  public init(
    model: SystemLanguageModel = .default,
    instructions: String? = nil,
    modelIdentifier: String = "apple/foundation-model"
  )

  /// Non-streaming response.
  public func respond(
    to prompt: String,
    promptCapture: Terra.CaptureIntent = .default
  ) async throws -> String

  /// Structured output via @Generable.
  public func respond<T: Generable>(
    to prompt: String,
    generating type: T.Type,
    promptCapture: Terra.CaptureIntent = .default
  ) async throws -> T

  /// Streaming response.
  public func streamResponse(
    to prompt: String,
    promptCapture: Terra.CaptureIntent = .default
  ) -> AsyncThrowingStream<String, Error>
}
```
Also aliased as `Terra.TracedSession`.

### TerraMLX — `TerraMLX.traced()`
```swift
@discardableResult
public static func traced<R>(
  model: String,
  maxTokens: Int? = nil,
  temperature: Double? = nil,
  device: String? = nil,
  memoryFootprintMB: Double? = nil,
  modelLoadDurationMS: Double? = nil,
  _ body: @Sendable () async throws -> R
) async throws -> R
```
Additional helpers:
- `TerraMLX.recordFirstToken()` — call from `didGenerate` when token count == 1
- `TerraMLX.recordTokenCount(_ count: Int)` — call periodically from `didGenerate`

### TerraLlama — `TerraLlama.traced()`
```swift
@discardableResult
public static func traced<R>(
  model: String,
  prompt: String? = nil,
  _ body: @Sendable (Terra.StreamingInferenceScope) async throws -> R
) async rethrows -> R
```
Additional helpers:
- `TerraLlama.applyDecodeStats(_ stats: DecodeStats, to scope: StreamingInferenceScope)`
- `TerraLlama.recordLayerMetrics(_ metrics: [LayerMetric], to scope: StreamingInferenceScope)`

`DecodeStats`:
```swift
public struct DecodeStats: Sendable {
  public var tokensPerSecond: Double?
  public var timeToFirstTokenMS: Double?
  public var kvCacheUsagePercent: Double?
}
```

`LayerMetric`:
```swift
public struct LayerMetric: Sendable {
  public var layerName: String
  public var durationMS: Double
  public var memoryMB: Double?
}
```

### @Traced Macro
```swift
@attached(body)
public macro Traced(model: String)
```
Auto-detects parameters named `prompt`/`input`/`query`/`text` and `maxTokens`/`maxOutputTokens`/`max_tokens`. Wraps the function body in `Terra.withInferenceSpan`. **Async functions only.**

Usage:
```swift
@Traced(model: "llama-3.2-1B")
func generate(prompt: String, maxTokens: Int = 512) async throws -> String {
  try await container.generate(prompt: prompt, maxTokens: maxTokens)
}
```
