# Terra API v3 — Agent-Optimized Clean Slate Design

**Date:** 2026-03-01
**Status:** Approved
**Priority:** Coding agents first, then developers

---

## Design Principles

1. **One obvious path per task** — agents should never hesitate about which API to use
2. **Closure-first** — the factory method IS the span, no `.run {}` ceremony
3. **Auto error recording** — all spans auto-catch and record errors
4. **Progressive disclosure** — beginners see 3 concepts, experts unlock 40+
5. **Protocol-oriented** — shared `Trace` protocol, typed extensions
6. **Macro-powered** — zero-boilerplate instrumentation for functions and expressions

---

## 1. Setup — Single Entry Point

### Current (v2)
```swift
// 4 competing entry points:
try await Terra.enable(.quickstart)
try Terra.start(.quickstart)
try Terra.install(Installation(...))
try Terra.installOpenTelemetry(OpenTelemetryConfiguration(...))
```

### New (v3)
```swift
// One method. Sync. Three presets.
try Terra.start()                          // quickstart (default)
try Terra.start(.production)               // on-device persistence
try Terra.start(.diagnostics)              // full logs + profiling

// With overrides
try Terra.start(.production) { config in
    config.privacy = .capturing
    config.endpoint = URL(string: "https://otel.myapp.com")!
}

// Full custom
try Terra.start(Terra.Configuration(
    privacy: .capturing,
    endpoint: myURL,
    serviceName: "MyApp"
))
```

### Configuration (flat, 3 essential + 8 advanced)
```swift
public struct Configuration: Sendable {
    // Essential (what 95% of users touch)
    public var privacy: Privacy = .redacted
    public var endpoint: URL = .otlpDefault
    public var serviceName: String? = nil          // auto-detected from bundle

    // Instruments
    public var instrumentations: Instrumentations = .automatic

    // Advanced (rarely needed)
    public var serviceVersion: String? = nil
    public var anonymizationKey: Data? = nil
    public var samplingRatio: Double? = nil
    public var persistence: PersistenceConfiguration? = nil
    public var metricsInterval: TimeInterval = 60
    public var enableSignposts: Bool = true
    public var enableSessions: Bool = true
    public var resourceAttributes: [String: String] = [:]
}
```

### Presets
```swift
public enum Preset: Sendable {
    /// Local development. Traces to localhost:4318. No persistence.
    case quickstart

    /// Production. On-device persistence. Privacy-first defaults.
    case production

    /// Full diagnostics: logs, memory/GPU profiling, OpenClaw.
    case diagnostics
}
```

### Errors (self-correcting messages)
```swift
public enum TerraError: Error, CustomStringConvertible {
    case alreadyStarted
    case invalidEndpoint(URL)

    public var description: String {
        switch self {
        case .alreadyStarted:
            "Terra.start() was already called. Call it once at app launch."
        case .invalidEndpoint(let url):
            "Invalid OTLP endpoint: \(url). Use a valid HTTP(S) URL."
        }
    }
}
```

### What's removed
- `Terra.enable()` — renamed to `Terra.start()`
- `Terra.install()` — merged into `start()`
- `Terra.installOpenTelemetry()` — merged into `start()`
- `Installation` struct — merged into `Configuration`
- `OpenTelemetryConfiguration` — flattened into `Configuration`
- `TracerProviderStrategy` — simplified (start handles it)
- Typo `defaultOltpHttp*` — fixed to `defaultOtlpHttp*`

---

## 2. Privacy — Simplified to 1 Enum

### Current (v2)
```swift
// 4 types to understand:
ContentPolicy (.never, .optIn, .always)
CaptureIntent (.default, .optIn)
RedactionStrategy (.drop, .lengthOnly, .hashHMACSHA256, .hashSHA256)
Privacy struct (contentPolicy, redaction, anonymizationKey, emitLegacySHA256Attributes)
```

### New (v3)
```swift
public enum Privacy: Sendable {
    /// Default. Content hashed with HMAC-SHA256. Privacy-first.
    case redacted

    /// Only capture string lengths. No content or hashes.
    case lengthOnly

    /// Full content capture. Use for development/debugging.
    case capturing

    /// Drop all content. Spans have structure only.
    case silent
}
```

### Per-call override (on builder only)
```swift
try await Terra.inference(model: "gpt-4")
    .includeContent()    // opt-in for this specific call
    .execute { ... }
```

### What's removed
- `ContentPolicy` — absorbed into `Privacy`
- `CaptureIntent` — replaced by `.includeContent()` builder method
- `RedactionStrategy` — absorbed into `Privacy` cases
- `Privacy` struct — replaced by `Privacy` enum
- `emitLegacySHA256Attributes` — removed (breaking change)

---

## 3. Spans — Closure-First API

### Current (v2)
```swift
// Two APIs coexist:
// V1 (closure-based):
try await Terra.withInferenceSpan(request) { scope in ... }

// V2 (fluent builder):
try await Terra.inference(model: "gpt-4").run { trace in ... }
```

### New (v3) — Factory Method IS the Span
```swift
// Simple (trailing closure = span body)
let result = try await Terra.inference(model: "gpt-4") {
    try await llm.generate("Hello")
}

// With metadata (named parameters)
let result = try await Terra.inference(
    model: "gpt-4",
    prompt: userMessage,
    provider: "openai",
    temperature: 0.7
) {
    try await llm.generate(userMessage)
}

// With trace context (closure parameter)
let result = try await Terra.inference(model: "gpt-4") { trace in
    let response = try await llm.generate("Hello")
    trace.tokens(input: 50, output: response.tokenCount)
    trace.responseModel(response.actualModel)
    return response.text
}
```

### All 6 Factory Methods
```swift
// Inference
Terra.inference(model:prompt:provider:runtime:temperature:maxOutputTokens:)

// Streaming
Terra.stream(model:prompt:provider:runtime:temperature:maxOutputTokens:)

// Agent
Terra.agent(name:id:provider:)

// Tool
Terra.tool(name:callID:type:provider:)

// Embedding
Terra.embedding(model:inputCount:provider:)

// Safety Check
Terra.safetyCheck(name:subject:provider:)
```

Each factory has TWO overloads:
1. `_ body: @Sendable () async throws -> R` — no trace context
2. `_ body: @Sendable (TraceType) async throws -> R` — with trace context

### Auto Error Recording
All span factories internally wrap in do-catch:
```swift
static func inference<R>(..., _ body: () async throws -> R) async rethrows -> R {
    let span = tracer.spanBuilder(name: "gen_ai.inference").startSpan()
    do {
        let result = try await body()
        span.end()
        return result
    } catch {
        span.recordError(error)
        span.setStatus(.error)
        span.end()
        throw error
    }
}
```

### Builder Escape Hatch (for dynamic metadata)
```swift
try await Terra.inference(model: "gpt-4")
    .provider(computedProvider)
    .includeContent()
    .attribute("custom.key", dynamicValue)
    .attribute(Terra.Key.runtime, "mlx")
    .execute { ... }
    .execute { trace in ... }
```

Note: terminal is `.execute {}` not `.run {}` to distinguish from the direct closure-first API.

### What's removed
- All `withSpan` methods (`withInferenceSpan`, `withStreamingInferenceSpan`, etc.)
- `StreamingRequest` — merged, `Terra.stream()` uses `InferenceRequest` internally
- `.run {}` on builders — renamed to `.execute {}`
- `Scope<Kind>` phantom types — replaced by `Trace` protocol

---

## 4. Trace Protocol — Shared Base

### Current (v2)
6 trace structs each redeclare `.event()`, `.attribute()`, `.emit()`.

### New (v3)
```swift
public protocol Trace: Sendable {
    @discardableResult func event(_ name: String) -> Self
    @discardableResult func attribute(_ key: String, _ value: String) -> Self
    @discardableResult func attribute(_ key: String, _ value: Int) -> Self
    @discardableResult func attribute(_ key: String, _ value: Double) -> Self
    @discardableResult func attribute(_ key: String, _ value: Bool) -> Self
    @discardableResult func attribute<V: TelemetryValue>(_ key: AttributeKey<V>, _ value: V) -> Self
    @discardableResult func emit<E: TerraEvent>(_ event: E) -> Self
    func recordError(_ error: any Error)
}

// Inference-specific
public struct InferenceTrace: Trace {
    @discardableResult public func tokens(input: Int?, output: Int?) -> Self
    @discardableResult public func responseModel(_ value: String) -> Self
}

// Streaming-specific
public struct StreamingTrace: Trace {
    @discardableResult public func chunk(tokens: Int) -> Self
    @discardableResult public func outputTokens(_ total: Int) -> Self
    @discardableResult public func firstToken() -> Self
}

// Others — protocol only, no extra methods
public struct AgentTrace: Trace { ... }
public struct ToolTrace: Trace { ... }
public struct EmbeddingTrace: Trace { ... }
public struct SafetyCheckTrace: Trace { ... }
```

Attributes support both raw strings (agent-friendly) and typed keys (expert-friendly):
```swift
trace.attribute("custom.key", "value")          // string key
trace.attribute(Terra.Key.provider, "openai")   // typed key
```

---

## 5. Constants — Flattened

### Current (v2)
```swift
Terra.Keys.GenAI.requestModel      // 4 levels deep
Terra.Keys.Terra.promptLength      // mixed namespaces
```

### New (v3)
```swift
extension Terra {
    public enum Key {
        public static let model = AttributeKey<String>("gen_ai.request.model")
        public static let responseModel = AttributeKey<String>("gen_ai.response.model")
        public static let maxTokens = AttributeKey<Int>("gen_ai.request.max_tokens")
        public static let temperature = AttributeKey<Double>("gen_ai.request.temperature")
        public static let inputTokens = AttributeKey<Int>("gen_ai.usage.input_tokens")
        public static let outputTokens = AttributeKey<Int>("gen_ai.usage.output_tokens")
        public static let provider = AttributeKey<String>("gen_ai.provider.name")
        public static let runtime = AttributeKey<String>("terra.runtime")
        public static let agentName = AttributeKey<String>("gen_ai.agent.name")
        public static let toolName = AttributeKey<String>("gen_ai.tool.name")
        public static let timeToFirstToken = AttributeKey<Double>("terra.stream.time_to_first_token_ms")
        public static let tokensPerSecond = AttributeKey<Double>("terra.stream.tokens_per_second")
        public static let contentPolicy = AttributeKey<String>("terra.privacy.content_policy")
    }
}
```

---

## 6. Macro System — Comprehensive

### 6.1 Function-Level: `@Traced`

```swift
// Inference
@Traced(model: "gpt-4")
@Traced(model: "gpt-4", provider: "openai", runtime: "mlx")
func generate(prompt: String) async throws -> String { ... }

// Streaming
@Traced(model: "gpt-4", streaming: true)
func streamGenerate(prompt: String) async throws -> AsyncThrowingStream<String, Error> { ... }

// Agent
@Traced(agent: "ResearchAgent")
func research(topic: String) async throws -> Report { ... }

// Tool (auto-generates callID)
@Traced(tool: "web-search")
func search(query: String) async throws -> [Result] { ... }

// Embedding
@Traced(embedding: "text-embedding-3-small")
func embed(texts: [String]) async throws -> [[Float]] { ... }

// Safety
@Traced(safety: "content-filter")
func checkContent(text: String) async throws -> Bool { ... }
```

### Macro declarations
```swift
@attached(body) public macro Traced(
    model: String, streaming: Bool = false,
    provider: String? = nil, runtime: String? = nil
) = #externalMacro(...)

@attached(body) public macro Traced(agent: String, id: String? = nil) = #externalMacro(...)
@attached(body) public macro Traced(tool: String, type: String? = nil) = #externalMacro(...)
@attached(body) public macro Traced(embedding: String) = #externalMacro(...)
@attached(body) public macro Traced(safety: String) = #externalMacro(...)
```

### Auto-detection table
| Parameter pattern | Maps to | Span types |
|---|---|---|
| `prompt`, `input`, `query`, `text`, `message`, first `String` | prompt | inference, streaming |
| `maxTokens`, `maxOutputTokens`, `max_tokens`, `*max*` + Int | maxOutputTokens | inference, streaming |
| `temperature`, `temp`, `creativity` + Double | temperature | inference, streaming |
| `provider` + String | provider | all |
| `callID`, `toolCallID`, `call_id` | callID | tool |
| `subject`, `content` | subject | safety |
| `count`, `inputCount` | inputCount | embedding |
| `stream`, `streaming` + Bool | streaming mode switch | inference |

### Auto error recording
All macro expansions wrap in do-catch:
```swift
@Traced(model: "gpt-4")
func generate(prompt: String) async throws -> String { ... }

// Expands to:
func generate(prompt: String) async throws -> String {
    try await Terra.inference(model: "gpt-4", prompt: prompt) { trace in
        do {
            return try await /* original body */
        } catch {
            trace.recordError(error)
            throw error
        }
    }
}
```

### 6.2 Class-Level: `@Traced` on Types

```swift
@Traced(model: "gpt-4", provider: "openai")
class LLMService {
    func chat(prompt: String) async throws -> String { ... }
    func summarize(text: String) async throws -> String { ... }
    func classify(input: String) async throws -> Category { ... }
}
// ALL async methods auto-wrapped in inference spans
```

Uses `@attached(memberAttribute)` to propagate `@Traced` to qualifying methods.

### 6.3 Agent Lifecycle: `@TerraAgent`

```swift
@TerraAgent(name: "ResearchAgent")
struct ResearchAgent {
    @Tool var search = WebSearch()
    @Tool var calculator = Calculator()

    @Step(1) func plan(task: String) async throws -> Plan { ... }
    @Step(2) func gather(plan: Plan) async throws -> [Finding] { ... }
    @Step(3) func synthesize(findings: [Finding]) async throws -> Report { ... }
}
```

**Auto-generates:**
- `run()` method wrapping all `@Step` methods in an agent span
- Per-step start/complete events with timing
- Tool accumulation: which tools declared vs used
- Model accumulation: which models called
- Step count, iteration tracking

**Resulting span:**
```
AgentSpan: "ResearchAgent"
├── attributes: tools.declared, tools.used, tools.count, models.used, step_count
├── events: step.started(plan,1) → step.completed(plan,1,280ms), ...
├── Step 1: plan
│   └── InferenceSpan
├── Step 2: gather
│   ├── ToolSpan: "search"
│   └── ToolSpan: "search"
└── Step 3: synthesize
    └── InferenceSpan
```

### 6.4 Expression Macro: `#trace`

```swift
// Inline trace (auto errors, auto callID for tools)
let result = try await #trace(model: "gpt-4") {
    try await llm.generate("Hello")
}

// With trace context
let result = try await #trace(model: "gpt-4") { trace in
    trace.tokens(input: 10, output: 50)
    return try await llm.generate("Hello")
}

// All span types
#trace(agent: "name") { ... }
#trace(tool: "search") { ... }        // auto UUID callID
#trace(tool: "search", callID: id) { ... }
#trace(embedding: "ada-002") { ... }
#trace(safety: "filter") { ... }
```

**Benefits over direct API:**
- Unified `#trace` vs 6 `Terra.*` methods
- Auto-generates tool callIDs
- ~30% shorter than direct API
- Visual consistency in pipelines

**Technical note:** Requires Swift 6.2 trailing closure support for expression macros. If unsupported, defer to direct API only.

### 6.5 Return Value Extraction: `TerraTraceable`

```swift
public protocol TerraTraceable {
    var terraTokenUsage: TokenUsage? { get }
    var terraResponseModel: String? { get }
}

public struct TokenUsage: Sendable {
    public var input: Int?
    public var output: Int?
}
```

When `@Traced` or `#trace` returns a `TerraTraceable` type, tokens auto-recorded:

```swift
struct LLMResponse: TerraTraceable {
    let text: String
    let inputTokens: Int
    let outputTokens: Int
    let model: String

    var terraTokenUsage: TokenUsage? { .init(input: inputTokens, output: outputTokens) }
    var terraResponseModel: String? { model }
}

@Traced(model: "gpt-4")
func generate(prompt: String) async throws -> LLMResponse {
    try await api.complete(prompt)
}
// Token counts auto-extracted from return value!
```

Auto-conformance macro:
```swift
@TerraTraceable
struct OpenAIResponse {
    let text: String
    let usage: Usage      // scanned for *tokens* properties
    let model: String     // scanned for *model* properties
}
```

### 6.6 Metrics-Only: `#instrument`

```swift
// Record duration/success without creating a span
let cleaned = #instrument("data.clean") { cleaner.clean(raw) }
```

For performance-critical inner loops where span overhead matters.

---

## 7. Agent Tree Mechanism

### Span nesting (automatic via OTel context)
```swift
try await Terra.agent(name: "Orchestrator") {
    try await Terra.inference(model: "gpt-4") { ... }  // child of Orchestrator
    try await Terra.tool(name: "search", callID: id) { ... }  // child of Orchestrator
}
```

### Task-local agent context (runtime metadata accumulation)
```swift
// Internal: when Terra.agent() starts, creates AgentContext as task-local
// When Terra.inference() executes inside, registers model with context
// When Terra.tool() executes inside, registers tool with context
// When agent span ends, accumulated data written as attributes:
//   terra.agent.tools.used, terra.agent.tools.count
//   terra.agent.models.used, terra.agent.inferences
```

### Span links (inference → tool relationships)
```swift
// Builder method to link tool span to triggering inference
try await Terra.tool(name: "search", callID: decision.callID)
    .linkedTo(decision)
    .execute { ... }

// Or auto-linking via @TerraAgent(autoLink: true)
```

---

## 8. Foundation Models Integration

### Terra.Session — Drop-In Replacement
```swift
let session = Terra.Session(
    model: .default,
    instructions: "You are helpful.",
    tools: [SearchTool()]
)

// Mirrors LanguageModelSession API exactly
let response = try await session.respond(to: "Hello")
let weather = try await session.respond(to: "Weather?", generating: WeatherReport.self)
for try await chunk in session.streamResponse(to: "Write a story") { ... }
```

### Auto-captured telemetry

| Feature | What's captured |
|---|---|
| Every `respond()` call | Inference span with duration, session turn, transcript length |
| Structured output | Response type name, field names, `terra.fm.structured_output` |
| Streaming | TTFT (first non-empty chunk), chunk count, total characters |
| Structured streaming | Time to first field, per-field completion events |
| Tool calls | Transcript diff → tool call events + reconstructed tool spans |
| Guardrail violations | Safety check span with violation details |
| Context overflow | Span error with `terra.fm.context_overflow` |
| Rate limiting | Span error with `terra.fm.rate_limited` |
| GenerationOptions | Temperature, sampling mode, max tokens as attributes |
| Session prewarm | Event: `terra.fm.prewarm` |

### Tool call capture via transcript inspection
After each `respond()` call, Terra diffs the transcript to discover internal tool calls:
```
InferenceSpan: "apple/foundation-model"
├── events:
│   tool_call { tool: "findRestaurants", args: {query: "Italian"} }
│   tool_result { tool: "findRestaurants" }
│   tool_call { tool: "bookTable", args: {restaurant: "Osteria"} }
│   tool_result { tool: "bookTable" }
├── attributes:
│   terra.fm.tools.declared = ["findRestaurants", "bookTable"]
│   terra.fm.tools.called = ["findRestaurants", "bookTable"]
│   terra.fm.tool_call_count = 2
```

### Structured streaming field tracking
```
StreamingSpan: "apple/foundation-model"
├── terra.fm.response_type = "WeatherReport"
├── events:
│   field_generated { field: "temperature", elapsed_ms: 200 }
│   field_generated { field: "condition", elapsed_ms: 350 }
│   field_generated { field: "humidity", elapsed_ms: 500 }
```

---

## 9. Complete API Surface Summary

```
SETUP (1 method, 3 presets)
  Terra.start()
  Terra.start(.quickstart | .production | .diagnostics)
  Terra.start(.preset) { config in ... }
  Terra.Configuration

PRIVACY (1 enum)
  Terra.Privacy: .redacted | .lengthOnly | .capturing | .silent

SPANS — DIRECT API (6 factories, trailing closure)
  Terra.inference(model:prompt:provider:runtime:temperature:maxOutputTokens:) { }
  Terra.inference(model:...) { trace in }
  Terra.stream(model:...) { trace in }
  Terra.agent(name:id:) { }
  Terra.tool(name:callID:type:) { }
  Terra.embedding(model:inputCount:) { }
  Terra.safetyCheck(name:subject:) { }

SPANS — BUILDER (escape hatch)
  Terra.inference(model:)
    .provider() .runtime() .includeContent()
    .attribute(String, Value) .attribute(AttributeKey, Value)
    .execute { }

TRACE PROTOCOL (shared)
  trace.event(String)
  trace.attribute(String|Key, Value)
  trace.emit(TerraEvent)
  trace.recordError(Error)

TRACE — TYPE-SPECIFIC
  InferenceTrace:  .tokens(input:output:) .responseModel(String)
  StreamingTrace:  .chunk(tokens:) .outputTokens(Int) .firstToken()

MACROS — FUNCTION-LEVEL
  @Traced(model:) @Traced(model:, streaming: true)
  @Traced(agent:) @Traced(tool:) @Traced(embedding:) @Traced(safety:)

MACROS — CLASS-LEVEL
  @Traced(model:) on class/struct — instruments all async methods

MACROS — AGENT LIFECYCLE
  @TerraAgent(name:) with @Step, @Tool, @Model markers

MACROS — EXPRESSION
  #trace(model:) { } #trace(agent:) { } #trace(tool:) { }

MACROS — PROTOCOL
  TerraTraceable — auto-extract tokens from return values
  @TerraTraceable — auto-generate conformance

MACROS — METRICS
  #instrument("label") { } — metrics without spans

FOUNDATION MODELS
  Terra.Session — drop-in for LanguageModelSession
  Auto: duration, tool calls, guardrails, streaming, structured output

CONSTANTS
  Terra.Key.model, .provider, .inputTokens, .outputTokens, etc.

ERRORS
  TerraError.alreadyStarted, .invalidEndpoint(URL)
```

**Total discoverable symbols: ~45**
**Concepts for hello world: 2** (`Terra.start()` + `Terra.inference() { }`)
**Lines for hello world: 2**

---

## 10. Agent Decision Tree

| Agent prompt | Use |
|---|---|
| "Set up telemetry" | `try Terra.start()` |
| "Instrument this function" | `@Traced(model:)` on the function |
| "Instrument this class" | `@Traced(model:)` on the class |
| "Wrap this LLM call" | `#trace(model:) { }` inline |
| "Build an agent with tracking" | `@TerraAgent(name:)` on the struct |
| "Add Foundation Models tracing" | `Terra.Session(...)` drop-in |
| "Dynamic metadata needed" | Builder: `Terra.inference(model:).provider(x).execute { }` |
| "Metrics without span overhead" | `#instrument("label") { }` |
