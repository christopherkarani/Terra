# API Reference

Complete reference for Terra's public API surface.

> **Compatibility note:** `ModelID` and `ToolCallID` are deprecated wrappers kept for older call sites.
> New code should pass model names and tool call IDs as raw `String` values.

## Typed IDs

### ModelID

```swift
public struct ModelID: Codable, Hashable, Sendable
```

Uniquely identifies a model used for inference, embeddings, or agent operations.

| Parameter | Type | Description |
|-----------|------|-------------|
| `rawValue` | `String` | The model identifier string |

**When to use**: Pass to ``Terra/infer(_:prompt:provider:runtime:temperature:maxTokens:)``, ``Terra/stream(_:prompt:provider:runtime:temperature:maxTokens:expectedTokens:)``, ``Terra/embed(_:inputCount:provider:runtime:)``, and the compatibility overloads on ``Terra/agent(_:id:provider:runtime:)`` and ``Terra/tool(_:callId:type:provider:runtime:)`` when you are migrating from wrapper types.

**Constants pattern**:

```swift
// Canonical form uses raw strings
Terra.infer("gpt-4o-mini", prompt: "What is machine learning?")

// Compatibility wrapper for older call sites
extension Terra.ModelID {
    static let gpt4oMini = Self("gpt-4o-mini")
    static let claude3 = Self("claude-3-opus")
}
```

### ProviderID

```swift
public struct ProviderID: Codable, Hashable, Sendable
```

Identifies the provider or service responsible for model execution.

| Parameter | Type | Description |
|-----------|------|-------------|
| `rawValue` | `String` | The provider identifier string |

**When to use**: Tag calls with the upstream provider for billing and routing attribution.

**Example**:

```swift
Terra.ProviderID("openai")
Terra.ProviderID("anthropic")
Terra.ProviderID("coreml")
```

### RuntimeID

```swift
public struct RuntimeID: Codable, Hashable, Sendable
```

Identifies the execution runtime or backend.

| Parameter | Type | Description |
|-----------|------|-------------|
| `rawValue` | `String` | The runtime identifier string |

**When to use**: Distinguish between local (CoreML, MLX) and remote (HTTP API) execution paths.

**Example**:

```swift
Terra.RuntimeID("http_api")
Terra.RuntimeID("coreml")
Terra.RuntimeID("mlx")
```

### ToolCallID

```swift
public struct ToolCallID: Codable, Hashable, Sendable
```

Uniquely identifies a single tool invocation within an agent workflow.

| Parameter | Type | Description |
|-----------|------|-------------|
| `rawValue` | `String` | The tool call identifier string |

**Auto-generation**: When initialized with `init()`, a UUID is generated automatically.

```swift
// Auto-generated unique ID
let callId = Terra.ToolCallID()

// Explicit ID
let callId = Terra.ToolCallID("call-12345")
```

---

## Operation Factory Methods

### infer

```swift
public static func infer(
    _ model: String,
    prompt: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil,
    temperature: Double? = nil,
    maxTokens: Int? = nil
) -> Operation
```

Creates an inference operation for non-streaming model responses.

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `model` | `String` | (required) | The model to use for inference |
| `prompt` | `String?` | `nil` | The input prompt (optional; can be set at runtime) |
| `provider` | `ProviderID?` | `nil` | The provider name for attribution |
| `runtime` | `RuntimeID?` | `nil` | The execution runtime |
| `temperature` | `Double?` | `nil` | Sampling temperature (0.0-2.0) |
| `maxTokens` | `Int?` | `nil` | Maximum output tokens |

**Returns**: An ``Operation`` value that can be configured with ``Operation/capture(_:)`` or ``Operation/run(_:)-swift.method``.

**Example**:

```swift
try await Terra
    .infer(
        "gpt-4o-mini",
        prompt: "What is machine learning?",
        provider: Terra.ProviderID("openai"),
        runtime: Terra.RuntimeID("http_api"),
        temperature: 0.7,
        maxTokens: 500
    )
    .run { "response" }
```

### stream

```swift
public static func stream(
    _ model: String,
    prompt: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil,
    temperature: Double? = nil,
    maxTokens: Int? = nil,
    expectedTokens: Int? = nil
) -> Operation
```

Creates a streaming inference operation.

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `model` | `String` | (required) | The model to use |
| `prompt` | `String?` | `nil` | The input prompt |
| `provider` | `ProviderID?` | `nil` | The provider name |
| `runtime` | `RuntimeID?` | `nil` | The execution runtime |
| `temperature` | `Double?` | `nil` | Sampling temperature |
| `maxTokens` | `Int?` | `nil` | Maximum output tokens |
| `expectedTokens` | `Int?` | `nil` | Expected output token count for streaming metrics |

**Example**:

```swift
try await Terra
    .stream(
        "gpt-4o-mini",
        prompt: "Write a story",
        expectedTokens: 1000
    )
    .run { trace in
        trace.chunk(12)
        trace.firstToken()
        trace.outputTokens(256)
        return "streamed content..."
    }
```

### embed

```swift
public static func embed(
    _ model: String,
    inputCount: Int? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
) -> Operation
```

Creates an embedding operation.

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `model` | `String` | (required) | The embedding model |
| `inputCount` | `Int?` | `nil` | Number of input texts |
| `provider` | `ProviderID?` | `nil` | The provider name |
| `runtime` | `RuntimeID?` | `nil` | The execution runtime |

**Example**:

```swift
try await Terra
    .embed(
        "text-embedding-3-small",
        inputCount: 5
    )
    .run { [[0.1, 0.2, 0.3]] }
```

### agent

```swift
public static func agent(
    _ name: String,
    id: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
) -> Operation
```

Creates an agent invocation operation.

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `name` | `String` | (required) | The agent name |
| `id` | `String?` | `nil` | Unique agent instance ID |
| `provider` | `ProviderID?` | `nil` | The provider name |
| `runtime` | `RuntimeID?` | `nil` | The execution runtime |

**Example**:

```swift
try await Terra
    .agent("planner", id: "agent-42", provider: Terra.ProviderID("openai"))
    .run { "agent response" }
```

### tool

```swift
public static func tool(
    _ name: String,
    callId: String,
    type: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
) -> Operation
```

Creates a tool execution operation.

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `name` | `String` | (required) | The tool name |
| `callId` | `String` | required | Unique call identifier |
| `type` | `String?` | `nil` | Tool type (e.g., "web_search") |
| `provider` | `ProviderID?` | `nil` | The provider name |
| `runtime` | `RuntimeID?` | `nil` | The execution runtime |

**Example**:

```swift
try await Terra
    .tool(
        "web_search",
        callId: "call-1",
        type: "web_search"
    )
    .run { ["search results"] }
```

### safety

```swift
public static func safety(
    _ name: String,
    subject: String? = nil,
    provider: ProviderID? = nil,
    runtime: RuntimeID? = nil
) -> Operation
```

Creates a safety check operation.

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `name` | `String` | (required) | The safety check name |
| `subject` | `String?` | `nil` | Content to check |
| `provider` | `ProviderID?` | `nil` | The provider name |
| `runtime` | `RuntimeID?` | `nil` | The execution runtime |

---

## Operation Methods

### capture

```swift
public func capture(_ policy: CapturePolicy) -> Self
```

Sets the content capture policy for this operation.

```swift
enum CapturePolicy: Sendable, Hashable {
    case `default`       // Respects global privacy setting
    case includeContent   // Captures content for this call
}
```

**Example**:

```swift
Terra
    .infer("gpt-4o-mini", prompt: "debug query")
    .capture(.includeContent)
    .run { "response" }
```

### run(_:)

```swift
@discardableResult
public func run<R: Sendable>(
    _ body: @escaping @Sendable () async throws -> R
) async rethrows -> R

@discardableResult
public func run<R: Sendable>(
    _ body: @escaping @Sendable (TraceHandle) async throws -> R
) async rethrows -> R
```

Executes the operation with optional trace handle access.

**Parameters**

| Parameter | Type | Description |
|-----------|------|-------------|
| `body` | `() async throws -> R` | Synchronous execution without trace access |
| `body` | `(TraceHandle) async throws -> R` | Execution with trace handle for annotations |

**Returns**: The result of the body closure.

**Example**:

```swift
// Without trace handle
try await Terra
    .infer("gpt-4o-mini", prompt: "Hello")
    .run { "response" }

// With trace handle
try await Terra
    .infer("gpt-4o-mini", prompt: "Hello")
    .run { trace in
        trace.event("inference.start")
        trace.tokens(input: 5, output: 12)
        return "response"
    }
```

---

## TraceHandle Methods

The ``TraceHandle`` is passed to your ``Operation/run(_:)-swift.method`` closure for annotating spans.

### event(_:)

```swift
@discardableResult
public func event(_ name: String) -> Self
```

Adds a named event to the span.

**Parameters**

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | `String` | Event name |

**Example**:

```swift
trace.event("inference.start")
trace.event("guardrail.decision")
```

### tag(_:_:)

```swift
@discardableResult
public func tag<T: CustomStringConvertible & Sendable>(
    _ key: StaticString,
    _ value: T
) -> Self
```

Adds a string attribute to the span.

> **Note**: All values are stored as string attributes. For numeric aggregation (sums, percentiles), use ``tokens(input:output:)`` instead.

**Parameters**

| Parameter | Type | Description |
|-----------|------|-------------|
| `key` | `StaticString` | Attribute key |
| `value` | `T` | Attribute value (converted to String) |

**Example**:

```swift
trace.tag("user.tier", "pro")
trace.tag("model.size", "large")
```

### tokens(input:output:)

```swift
@discardableResult
public func tokens(input: Int? = nil, output: Int? = nil) -> Self
```

Records token usage on the span.

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `input` | `Int?` | `nil` | Number of input tokens |
| `output` | `Int?` | `nil` | Number of output tokens |

**Example**:

```swift
trace.tokens(input: 120, output: 45)
```

### responseModel(_:)

```swift
@discardableResult
public func responseModel(_ value: String) -> Self
```

Records the actual model that generated the response.

**Example**:

```swift
trace.responseModel("gpt-4o-mini")
```

`ModelID` remains accepted through a compatibility overload, but raw strings are the preferred form for new code.

### chunk(_:)

```swift
@discardableResult
public func chunk(_ tokens: Int = 1) -> Self
```

Records a streaming chunk (for streaming operations).

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `tokens` | `Int` | `1` | Number of tokens in chunk |

**Example**:

```swift
trace.chunk(12)
trace.chunk(8)
```

### outputTokens(_:)

```swift
@discardableResult
public func outputTokens(_ total: Int) -> Self
```

Records the total output token count.

**Example**:

```swift
trace.outputTokens(256)
```

### firstToken()

```swift
@discardableResult
public func firstToken() -> Self
```

Marks the time-to-first-token event.

**Example**:

```swift
trace.firstToken()
```

### recordError(_:)

```swift
public func recordError(_ error: any Error)
```

Records an error on the span.

**Example**:

```swift
do {
    try await riskyOperation()
} catch {
    trace.recordError(error)
    throw error
}
```

---

## Lifecycle

### start(_:)

```swift
public static func start(
    _ config: Configuration = .init()
) async throws
```

Starts Terra with the specified configuration.

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `config` | `Configuration` | `.init()` | Configuration with preset or custom settings |

**Throws**: ``TerraError`` with codes:

- `.invalid_endpoint` - Invalid OTLP endpoint URL
- `.already_started` - Terra is already running
- `.persistence_setup_failed` - Storage initialization failed
- `.invalid_lifecycle_state` - Invalid state transition

**Example**:

```swift
// Quickstart defaults
try await Terra.start()

// Explicit preset
try await Terra.start(.init(preset: .production))

// Custom configuration
var config = Terra.Configuration(preset: .production)
config.privacy = .redacted
try await Terra.start(config)
```

### shutdown()

```swift
public static func shutdown() async
```

Shuts down Terra gracefully, flushing pending telemetry.

**Example**:

```swift
await Terra.shutdown()
```

> **Note**: Safe to call from any context. Idempotent.

### reconfigure(_:)

```swift
public static func reconfigure(_ config: Configuration) async throws
```

Shuts down and restarts Terra with a new configuration.

**Parameters**

| Parameter | Type | Description |
|-----------|------|-------------|
| `config` | `Configuration` | New configuration |

**Throws**: ``TerraError`` if Terra is not currently running.

**Example**:

```swift
var newConfig = Terra.Configuration(preset: .diagnostics)
try await Terra.reconfigure(newConfig)
```

### reset()

```swift
public static func reset() async
```

Shuts down and clears all cached configuration state.

**Example**:

```swift
await Terra.reset()
// Terra.start() can now be called with any configuration
```

---

## Discovery and Manual Tracing

Terra also exposes a discoverability layer and explicit span lifecycle APIs for coding agents and advanced integrations.

### Discovery Helpers

- ``Terra/capabilities()``
- ``Terra/guides()``
- ``Terra/examples()``
- ``Terra/ask(_:)``
- ``Terra/diagnose()``

### Manual Tracing

- ``Terra/currentSpan()``
- ``Terra/isTracing()``
- ``Terra/startSpan(name:id:attributes:)``
- ``Terra/trace(name:id:_:)-swift.method``
- ``Terra/activeSpans()``
- ``Terra/visualize(_:)-swift.method``
- ``Terra/onSpanStart(_:)``
- ``Terra/onSpanEnd(_:)``
- ``Terra/onError(_:)``
- ``Terra/removeHooks()``
- ``Terra/register(_:)``

### Startup Helpers

- ``Terra/start(_:)``
- ``Terra/quickStart()``
- ``Terra/shutdown()``
- ``Terra/reset()``
- ``Terra/reconfigure(_:)``

These entry points are the right choice when you need explicit lifecycle ownership, a local-dev default, or machine-readable guidance for agents.

---

## Attribute Keys

### Terra.Keys.GenAI

OpenTelemetry-standard GenAI attribute keys.

| Key | Type | Description |
|-----|------|-------------|
| `operationName` | `String` | Operation type: "inference", "embeddings", etc. |
| `requestModel` | `String` | Requested model identifier |
| `requestMaxTokens` | `Int` | Maximum tokens requested |
| `requestTemperature` | `Double` | Sampling temperature |
| `requestStream` | `Bool` | Whether streaming was requested |
| `usageInputTokens` | `Int` | Actual input token count |
| `usageOutputTokens` | `Int` | Actual output token count |
| `responseModel` | `String` | Model that generated response |
| `providerName` | `String` | Provider name |
| `agentName` | `String` | Agent name |
| `agentID` | `String` | Agent instance ID |
| `toolName` | `String` | Tool name |
| `toolType` | `String` | Tool type |
| `toolCallID` | `String` | Tool call ID |

### Terra.Keys.Terra

Terra-specific attribute keys.

#### Content Privacy

| Key | Type | Description |
|-----|------|-------------|
| `promptLength` | `Int` | Prompt character count |
| `promptHMACSHA256` | `String` | HMAC-SHA256 hash of prompt |
| `promptSHA256` | `String` | Legacy SHA256 hash of prompt |
| `safetySubjectLength` | `Int` | Safety check subject length |
| `safetySubjectHMACSHA256` | `String` | HMAC-SHA256 hash of subject |
| `anonymizationKeyID` | `String` | Key ID used for hashing |

#### Streaming

| Key | Type | Description |
|-----|------|-------------|
| `streamTimeToFirstTokenMs` | `Double` | Time to first token in milliseconds |
| `streamTokensPerSecond` | `Double` | Token generation rate |
| `streamOutputTokens` | `Int` | Total output tokens |
| `streamChunkCount` | `Int` | Number of chunks received |
| `streamFirstTokenEvent` | `String` | Event name for first token |

#### Runtime

| Key | Type | Description |
|-----|------|-------------|
| `runtime` | `String` | Runtime identifier (e.g., "coreml", "http_api") |
| `thermalState` | `String` | Process thermal state |
| `autoInstrumented` | `Bool` | Whether span came from auto-instrumentation |

#### Compute

| Key | Type | Description |
|-----|------|-------------|
| `modelSizeBytes` | `Int` | Model size in bytes |
| `modelSizeMB` | `Double` | Model size in MB |
| `modelFormat` | `String` | Model format (e.g., "coreml", "mlx") |
| `modelComputeDeviceGuess` | `String` | Likely compute device |

---

## Custom Attributes

### Adding Attributes with TraceHandle

Use the ``TraceHandle/tag(_:_:)`` method inside the ``Operation/run(_:)`` closure to add custom string attributes:

```swift
import Terra

// Use in operations
try await Terra
    .infer("gpt-4o-mini", prompt: prompt)
    .run { trace in
        trace.tag("app.user_tier", "pro")
        trace.tag("app.request_id", UUID().uuidString)
        return "response"
    }
```

> **Note:** ``TraceHandle/tag(_:_:)`` stores values as OpenTelemetry string attributes.
> For numeric aggregation (sums, percentiles), use ``TraceHandle/tokens(input:output:)`` instead.

---

## See Also

- <doc:Canonical-API> - Complete API map
- <doc:Typed-IDs> - Typed ID guide
- <doc:Configuration-Reference> - Configuration options
- <doc:Metadata-Builder> - Metadata patterns
