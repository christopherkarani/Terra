# Terra Framework - Comprehensive Technical Analysis

> **Generated**: 2026-03-25
> **Purpose**: Complete understanding of Terra's architecture, patterns, and unique characteristics

---

## Executive Summary

**Terra** is an on-device GenAI observability framework built on OpenTelemetry Swift. It instruments model inference, streaming, agents, tool calls, embeddings, safety checks, Core ML calls, and HTTP AI requests with privacy-first design (content capture is opt-in by default, export is local).

**Key Differentiators**:
- Privacy-first architecture with configurable redaction strategies (drop, length-only, HMAC-SHA256, legacy SHA256)
- Multi-tier observability: tracing, metrics, logging with unified semantic conventions for GenAI
- Native Apple framework integrations: CoreML, Metal, ANE, Accelerate
- Compiler plugin (`@Traced` macro) for automatic instrumentation
- Local-first with optional OTLP export
- Zig-native core with C ABI bridge for cross-language support

---

## Module Architecture

### Package Products (from Package.swift)

| Product | Purpose |
|--------|---------|
| `Terra` | Umbrella target with auto-instrumentation and lifecycle setup |
| `TerraCore` | Core API, privacy, lifecycle, and trace types |
| `TerraCoreML` | Core ML instrumentation helpers |
| `TerraTraceKit` | OpenTelemetry helpers and renderers |
| `TerraHTTPInstrument` | HTTP AI request instrumentation |
| `TerraFoundationModels` | Apple Foundation Models integration |
| `TerraMLX` | MLX integration helpers |
| `TerraMetalProfiler` | Metal profiling hooks |
| `TerraSystemProfiler` | Memory profiling hooks |
| `TerraAccelerate` | Accelerate backend attributes |
| `TerraTracedMacro` | `@Traced` macro support |

### Source Structure

```
Sources/
├── Terra/                    # TerraCore implementation (23 files)
│   ├── Terra.swift           # Main enum with inference/agent/tool spans
│   ├── Terra+Runtime.swift   # Runtime singleton, lifecycle state machine
│   ├── Terra+Privacy.swift   # Privacy configuration and redaction
│   ├── Terra+FluentAPI.swift  # Builder pattern API
│   ├── Terra+Scope.swift     # Scope types for spans
│   ├── Terra+Requests.swift   # Request models
│   └── ...
├── TerraTraceKit/            # Trace visualization and OTLP
│   ├── Trace.swift           # Trace model from spans
│   ├── Models.swift          # TraceID, SpanID, Attributes
│   ├── TraceStore.swift      # In-memory span store
│   ├── OTLPHTTPServer.swift  # HTTP OTLP receiver
│   └── ...
├── TerraHTTPInstrument/      # URLSession instrumentation
│   ├── HTTPAIInstrumentation.swift
│   ├── AIRequestParser.swift
│   └── AIResponseParser.swift
├── TerraTracedMacro/         # @Traced macro
│   └── Traced.swift
├── TerraTracedMacroPlugin/   # Compiler plugin
│   └── TracedMacro.swift
├── TerraAutoInstrument/      # Auto-instrumentation setup
│   ├── OpenClawConfiguration.swift
│   └── OpenClawDiagnosticsExporter.swift
├── TerraCoreML/             # CoreML instrumentation
├── TerraFoundationModels/     # Apple FM integration
├── TerraMLX/                # MLX array integration
├── TerraLlama/               # Llama.cpp integration
├── TerraAccelerate/          # Accelerate backend
├── TerraMetalProfiler/       # Metal GPU profiling
├── TerraSystemProfiler/      # System memory/CPU profiling
├── TerraANEProfiler/         # Apple Neural Engine profiling
├── TerraPowerProfiler/       # Power/energy profiling
├── CTerraBridge/             # C ABI bridge to Zig core
└── CTerraANEBridge/         # ANE C bridge
```

---

## Core Architecture

### 1. Terra Main Entry Point (`Terra.swift`)

Terra is a **public enum** (not a class) providing a clean static API facade over OpenTelemetry.

```swift
public enum Terra {
  package static let instrumentationName: String = "io.opentelemetry.terra"
  package static let instrumentationVersion: String? = nil
}
```

**Core Span Types** (via `with*Span` methods):
- `withInferenceSpan` - LLM inference calls
- `withStreamingInferenceSpan` - Streaming responses with TTFT/TPS tracking
- `withAgentInvocationSpan` - Agent orchestration
- `withToolExecutionSpan` - Tool/function calls
- `withEmbeddingSpan` - Embedding generation
- `withSafetyCheckSpan` - Content moderation

### 2. Runtime & Lifecycle (`Terra+Runtime.swift`)

**Lifecycle State Machine**:
```swift
public enum LifecycleState: Sendable, Equatable {
  case stopped       // Not started or shut down
  case starting     // Start in progress
  case running       // Active telemetry collection
  case shuttingDown  // Shutdown in progress
}
```

**Runtime Singleton** (`final class Runtime`):
- Uses **NSLock** for thread safety (not actor, matching existing patterns)
- Manages privacy settings, tracer/meter/logger providers
- Stores anonymization key in iOS Keychain
- Tracks lifecycle state transitions

**Anonymization Key Management**:
- 32-byte random key generated via `SecRandomCopyBytes`
- Stored in Keychain with service: `io.opentelemetry.terra`
- Used for HMAC-SHA256 content hashing
- Key ID derived as first 16 chars of SHA256 of key

### 3. Privacy System (`Terra+Privacy.swift`)

**Content Policy** (when to capture):
```swift
enum ContentPolicy: Sendable, Hashable {
  case never        // Never capture content
  case optIn        // Only if includeContent=true
  case always       // Always capture (not recommended)
}
```

**Redaction Strategies** (how to handle captured content):
```swift
enum RedactionStrategy: Sendable, Hashable {
  case drop           // Discard content entirely
  case lengthOnly     // Only record length
  case hashHMACSHA256 // HMAC with rotating key (default)
  case hashSHA256     // Legacy deterministic hash
}
```

**Unique Privacy Features**:
- Per-request privacy override via `.includeContent()`
- HMAC-SHA256 provides reversible anonymization (key stored)
- Legacy SHA256 for compatibility with existing systems
- Content dropped by default - explicit opt-in required

### 4. Request/Response Models (`Terra+Requests.swift`)

Key request types:
- `InferenceRequest` - Model ID, prompt, temperature, maxTokens, includeContent
- `StreamingRequest` - Extends InferenceRequest with expectedOutputTokens
- `EmbeddingRequest` - Model ID, inputCount
- `AgentRequest` - Agent name, optional ID
- `ToolRequest` - Tool name, callID, type
- `SafetyCheckRequest` - Check name, subject

### 5. Fluent API (`Terra+FluentAPI.swift`)

Builder pattern for all operations:

```swift
try await Terra
  .infer(Terra.ModelID("gpt-4o-mini"), prompt: prompt)
  .provider("openai")
  .temperature(0.7)
  .tokens(input: 128, output: 64)
  .execute { trace in
    trace.tokens(input: 128, output: 64)
    return try await llm.generate(prompt)
  }
```

**Call Types** (all Sendable structs):
- `InferenceCall`, `StreamingCall`, `EmbeddingCall`
- `AgentCall`, `ToolCall`, `SafetyCheckCall`

**AttributeBag** - Type-safe attribute storage:
```swift
struct AttributeKey<Value: TelemetryValue>: Sendable, Hashable {
  let name: String
}

struct AttributeBag: Sendable, Hashable {
  var values: [String: TelemetryAttributeValue]
  mutating func set<Value: TelemetryValue>(_ key: AttributeKey<Value>, _ value: Value)
}
```

### 6. Scope Types (`Terra+Scope.swift`)

Generic scope wrappers around OpenTelemetry spans:
- `Scope<InferenceSpan>`, `Scope<StreamingInferenceScope>`
- `Scope<AgentInvocationSpan>`, `Scope<ToolExecutionSpan>`
- `Scope<EmbeddingSpan>`, `Scope<SafetyCheckSpan>`

Each scope provides:
- `setAttributes()` - Add/modify attributes
- `addEvent()` - Log events with timestamp
- `recordError()` - Record exceptions
- Type-specific helpers (e.g., `tokens()`, `responseModel()`)

### 7. Streaming Inference (`StreamingInferenceScope`)

Thread-safe token tracking with NSLock:

```swift
final class StreamingInferenceScope: @unchecked Sendable {
  private let lock = NSLock()
  private var firstTokenAt: ContinuousClock.Instant?
  private var outputTokenCount = 0
  private var chunkCount = 0
}
```

**Tracked Metrics**:
- `terra.first_token` event (first token timestamp)
- `terra.stream.chunk_count` - Total chunks received
- `terra.stream.output_tokens` - Total output tokens
- `terra.stream.time_to_first_token_ms` - TTFT
- `terra.stream.tokens_per_second` - Generation speed

---

## TraceKit - Local Trace Visualization

### Trace Model (`Trace.swift`)

Aggregated trace from persisted spans:
```swift
public struct Trace {
  public let id: String                    // Filename-derived
  public let fileTimestamp: Date
  public let traceID: TraceId
  public let spans: [SpanData]
  public let orderedSpans: [SpanData]      // By start/end time
  public let rootSpans: [SpanData]         // No parent
  public let startTime: Date
  public let endTime: Date
  public let duration: TimeInterval
  public let hasError: Bool
  public let displayName: String
}
```

### TraceID & SpanID (`Models.swift`)

128-bit trace IDs with big-endian byte order:
```swift
public struct TraceID: Hashable, Sendable, Comparable {
  public let hi: UInt64  // High 64 bits
  public let lo: UInt64  // Low 64 bits
}

public struct SpanID: Hashable, Sendable, Comparable {
  public let rawValue: UInt64
}
```

### Attribute System (`Models.swift`)

**AttributeValue** - Tagged union:
```swift
public enum AttributeValue: Hashable, Sendable {
  case string(String)
  case bool(Bool)
  case int(Int64)
  case double(Double)
  case bytes([UInt8])
  case array([AttributeValue])
  case kvlist([Attribute])
  case null
}
```

**Attributes** - Sorted, searchable container:
- Binary search for O(log n) lookups
- Stable sort key for deterministic ordering
- Dictionary-style access: `attributes["key"]`

### TraceStore (`TraceStore.swift`)

**Actor-based** in-memory span store:
```swift
public actor TraceStore {
  private var spansByKey: [SpanKey: SpanRecord] = [:]
  private var insertionOrder: [SpanKey] = []
  private var cachedSnapshot: TraceSnapshot?
}
```

**Key Features**:
- Deduplication by (traceID, spanID)
- LRU eviction when exceeding `maxSpans`
- Cached snapshots with dirty tracking
- Efficient grouping by traceID

### OTLP HTTP Server (`OTLPHTTPServer.swift`)

Custom lightweight OTLP receiver (not using OpenTelemetry SDK):
```swift
public final class OTLPHTTPServer {
  private let decoder: OTLPRequestDecoder
  private let traceStore: TraceStore
  private let queue = DispatchQueue(label: "terra.trace.otlp.httpserver")
  private var listener: NWListener?
  private var activeConnections: [ObjectIdentifier: NWConnection] = [:]
}
```

**Capabilities**:
- Accepts POST `/v1/traces`
- Supports gzip/deflate compression
- Limits: max body 10MB, decompressed 50MB, 10K spans/request
- Case-insensitive header matching
- Read timeouts (5s headers, 15s body)
- Max 64 concurrent connections

### OTLP Decoder (`OTLPDecoder.swift`)

Protobuf parsing with validation:
```swift
public struct OTLPRequestDecoder: Sendable {
  public struct Limits: Sendable, Hashable {
    public var maxBodyBytes: Int           // Default: 10MB
    public var maxDecompressedBytes: Int    // Default: 50MB
    public var maxSpansPerRequest: Int      // Default: 10K
    public var maxAttributesPerSpan: Int    // Default: 256
    public var maxAnyValueDepth: Int       // Default: 8
  }
}
```

**GenAI Attribute Preservation**:
- Preserves `gen_ai.*` and `terra.*` resource attributes
- Maps OpenTelemetry span kinds/status codes
- Adds `span.kind` and `status.code` as string attributes

### Telemetry Classifier (`TerraTelemetryClassifier.swift`)

Categorizes events for UI filtering:
```swift
enum TerraTelemetryClassifier {
  // Recommendation events
  static let recommendationEventName = "terra.recommendation"
  static let recommendationAttributePrefix = "terra.recommendation."

  // Anomaly detection
  static let anomalyNamePrefix = "terra.anomaly"

  // Policy/audit events
  static let policyNamePrefix = "terra.policy"
  static let auditNamePrefix = "terra.audit"

  // Lifecycle events
  static let lifecycleEventNames = [
    "terra.first_token",
    "terra.token.lifecycle",
    "terra.stream.lifecycle",
  ]

  // Hardware events
  static let hardwareAttributeKeys = [
    "terra.process.thermal_state",
    "terra.hw.power_state",
    "terra.hw.ane_utilization_pct",
    // ...
  ]
}
```

---

## HTTP/AI Instrumentation

### HTTPAIInstrumentation (`HTTPAIInstrumentation.swift`)

Auto-instruments HTTP requests to AI providers:
```swift
public enum HTTPAIInstrumentation {
  public static let defaultAIHosts: Set<String> = [
    "api.openai.com",
    "api.anthropic.com",
    "generativelanguage.googleapis.com",
    "api.together.xyz",
    "api.mistral.ai",
    "api.groq.com",
    "api.cohere.com",
    "api.fireworks.ai",
  ]
}
```

**Installation**:
```swift
HTTPAIInstrumentation.install(
  hosts: defaultAIHosts,
  openClawGatewayHosts: ["localhost", "127.0.0.1"],
  openClawMode: "disabled"
)
```

**What Gets Instrumented**:
- Request body parsing (model, maxTokens, temperature, stream)
- Response parsing (usage tokens, response model)
- Provider inference from host
- OpenClaw gateway detection

### AI Request Parser (`AIRequestParser.swift`)

Extracts GenAI parameters from HTTP request bodies:
- OpenAI Chat API format
- Anthropic format
- Google Generative AI format
- Generic JSON extraction

### AI Response Parser (`AIResponseParser.swift`)

Extracts from responses:
- Model from response
- Input/output token counts
- Streaming chunk tracking

---

## ML/LLM Integrations

### TerraCoreML (`TerraCoreML.swift`)

Wraps CoreML inference:
- `MLModel` compilation and execution
- Input/output tracking
- Performance metrics

### TerraFoundationModels (`Terra+FoundationModels.swift`)

Apple's Foundation Models integration:
```swift
@available(macOS 26.0, iOS 26.0, *)
func ask(_ prompt: String) async throws -> String {
  let session = Terra.TracedSession(model: .default)
  return try await session.respond(to: prompt)
}
```

### TerraMLX (`Terra+MLX.swift`, `TerraMLX.swift`)

Apple MLX array framework:
```swift
TerraMLX.traced(
  model: Terra.ModelID("mlx-community/Llama-3.2-1B"),
  maxTokens: 256,
  temperature: 0.7,
  device: "ane",
  memoryFootprintMB: 512,
  modelLoadDurationMS: 1800
) {
  TerraMLX.recordFirstToken()
  TerraMLX.recordTokenCount(32)
  return "mlx output"
}
```

### TerraLlama (`TerraLlama.swift`)

Llama.cpp integration for local models.

### TerraAccelerate (`TerraAccelerate.swift`)

Accelerate framework backend attributes for BLAS/vecLib operations.

---

## TracedMacro - Compiler Plugin

### Macro Definition (`TerraTracedMacro/Traced.swift`)

```swift
@attached(body)
public macro Traced(
  model: Terra.ModelID,
  prompt: String? = nil,
  provider: Terra.ProviderID? = nil,
  runtime: Terra.RuntimeID? = nil,
  temperature: Double? = nil,
  maxTokens: Int? = nil,
  maxOutputTokens: Int? = nil,
  streaming: Bool = false
) = #externalMacro(module: "TerraTracedMacroPlugin", type: "TracedMacro")
```

**Variants**:
- `@Traced(model:)` - Inference
- `@Traced(agent:)` - Agent invocation
- `@Traced(tool:)` - Tool execution
- `@Traced(embedding:)` - Embedding
- `@Traced(safety:)` - Safety check

### Auto-Detection

The macro auto-detects common parameter names:
- **Prompt aliases**: `prompt`, `input`, `query`, `text`, `message`, `subject`
- **Max token aliases**: `maxTokens`, `maxOutputTokens`, `max_tokens`

### Usage Example

```swift
@Traced(model: Terra.ModelID("llama-3.2-1B"), provider: Terra.ProviderID("mlx"))
func generate(prompt: String, maxTokens: Int = 512) async throws -> String {
  try await container.generate(prompt: prompt, maxTokens: maxTokens)
}
```

---

## Auto-Instrumentation

### OpenClaw Configuration (`OpenClawConfiguration.swift`)

Central configuration for auto-instrumentation:
```swift
OpenClawConfiguration.install(
  preset: .production  // or .development, .diagnostics
)
```

### OpenClawDiagnosticsExporter (`OpenClawDiagnosticsExporter.swift`)

Exports diagnostics data for debugging.

---

## Profiler Modules

### TerraSystemProfiler

Captures system-level metrics:
- Memory snapshots (RSS, delta)
- Thermal state
- CPU usage

### TerraMetalProfiler

Metal GPU profiling:
- GPU utilization
- Memory pressure

### TerraANEProfiler

Apple Neural Engine:
- ANE utilization percentage
- Model execution on ANE

### TerraPowerProfiler

Energy consumption tracking.

---

## Test Infrastructure

### TerraTestSupport (`TerraTestSupport.swift`)

Lock-based test isolation:
```swift
TerraTestSupport.lockTestingIsolation()
defer { TerraTestSupport.unlockTestingIsolation() }
```

### Concurrency Testing

- `NSLock` for mutex isolation
- Swift Testing `@Suite(.serialized)` for suite-level serialization
- `lockTestingIsolation` required for any suite touching Terra singleton
- Port ranges: deterministic 14001-14099, concurrency 15001-15060

---

## Key Design Patterns

### 1. Facade Pattern
Terra enum provides clean static API over complex OpenTelemetry internals.

### 2. Builder Pattern
Fluent API with method chaining for configuration:
```swift
Terra.infer(model: "gpt-4o").provider("openai").temperature(0.7)
```

### 3. Scope/Context Pattern
Generic span wrappers providing type-safe access:
```swift
try await withSpan(...) { scope in
  scope.setAttributes([...])
  scope.recordError(error)
}
```

### 4. Actor Isolation
`TraceStore` uses actor for thread-safe state management.

### 5. Visitor/Strategy
`TerraTelemetryClassifier` categorizes events for different views.

### 6. Protocol Witnesses
`TelemetryValue` protocol allows extension of built-in types.

### 7. Keychain Security
Anonymization keys stored securely in iOS Keychain.

---

## OpenTelemetry Integration

### Semantic Conventions

GenAI-specific attributes:
- `gen_ai.operation.name` - Operation type
- `gen_ai.request.model` - Model ID
- `gen_ai.response.model` - Response model
- `gen_ai.usage.input_tokens` / `output_tokens`
- `gen_ai.request.temperature` / `max_tokens`

Terra-specific attributes:
- `terra.*` - Framework-specific metadata
- `service.name` - From resource
- `span.kind` / `status.code` - Normalized enums

### Provider Registration

Providers can be registered globally or kept private:
```swift
Installation(
  privacy: .default,
  meterProvider: nil,
  tracerProvider: nil,
  loggerProvider: nil,
  registerProvidersAsGlobal: true  // vs false for isolated
)
```

---

## Dependency Graph

```
Terra (Auto-Instrumentation)
├── TerraCore
│   ├── OpenTelemetryApi/Sdk
│   ├── TerraSystemProfiler
│   └── CTerraBridge (macOS only)
├── TerraCoreML
│   ├── TerraCore
│   └── TerraMetalProfiler
├── TerraHTTPInstrument
│   ├── TerraCore
│   └── URLSessionInstrumentation
├── TerraMetalProfiler
│   └── TerraSystemProfiler
└── OpenTelemetrySdk

TerraTracedMacro
├── TerraTracedMacroPlugin
└── TerraCore

TerraTraceKit
├── OpenTelemetryApi/Sdk
└── OpenTelemetryProtocolExporter
```

---

## Unique Innovations

### 1. Privacy-First Observability
Content is dropped by default. Users must explicitly opt-in. Even when capturing, HMAC-SHA256 provides reversible anonymization.

### 2. Streaming Telemetry
First-token time, tokens-per-second, chunk counts tracked automatically for streaming responses.

### 3. Multi-Framework Support
CoreML, Metal, ANE, MLX, Accelerate - all have specialized integrations for Apple's ML ecosystem.

### 4. Local-First Export
Built-in OTLP HTTP server allows local trace collection without cloud dependency.

### 5. Compiler Plugin Automation
`@Traced` macro reduces boilerplate by auto-detecting parameter names and generating span code.

### 6. Zig Native Core
High-performance core in Zig with C ABI, enabling bindings for Python, Rust, C++, Android, ROS2.

---

## Configuration Presets

```swift
// Production - minimal overhead
try await Terra.start(.init(preset: .production))

// Development - more verbose
try await Terra.start(.init(preset: .development))

// Diagnostics - full debug info
try await Terra.start(.init(preset: .diagnostics))
```

---

## Glossary

| Term | Definition |
|------|------------|
| **TTFT** | Time To First Token |
| **TPS** | Tokens Per Second |
| **HMAC** | Hash-based Message Authentication Code |
| **OTLP** | OpenTelemetry Line Protocol |
| **Span** | A unit of work in a trace |
| **Trace** | A collection of spans representing a request |
| **ANE** | Apple Neural Engine |
| **CoreML** | Apple CoreML framework |
| **MLX** | Apple's MLX array framework |

---

## Further Research Areas

1. **Zig Core Implementation** - The native core in `zig-core/` provides high-performance trace processing
2. **Cross-Language Bindings** - Python, Rust, C++, Android, ROS2 bindings share the Zig core
3. **Docc Documentation** - Full API reference in `Sources/TerraAutoInstrument/Terra.docc/`
4. **Benchmarks** - Performance benchmarks in `Benchmarks/TerraSDKBenchmarks/`
5. **Examples** - Working samples in `Examples/Terra Sample/` and `Examples/Terra Auto Instrument/`

---

*Document generated by Claude Code agent swarm exploring Terra framework codebase*
