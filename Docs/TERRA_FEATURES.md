# Terra — Comprehensive Feature Reference

Terra is an on-device GenAI observability SDK for Swift, built on OpenTelemetry. It instruments model inference, embeddings, agent steps, tool calls, and safety checks across Apple platforms with strong privacy defaults.

---

## Table of Contents

1. [Three-Tier Integration Model](#1-three-tier-integration-model)
2. [Span Types & Instrumentation](#2-span-types--instrumentation)
3. [Runtime Support](#3-runtime-support)
4. [Auto-Instrumentation: CoreML](#4-auto-instrumentation-coreml)
5. [Auto-Instrumentation: HTTP AI APIs](#5-auto-instrumentation-http-ai-apis)
6. [Foundation Models Integration](#6-foundation-models-integration)
7. [MLX Integration](#7-mlx-integration)
8. [llama.cpp Integration](#8-llamacpp-integration)
9. [Accelerate Framework Integration](#9-accelerate-framework-integration)
10. [Streaming Inference](#10-streaming-inference)
11. [Privacy & Content Control](#11-privacy--content-control)
12. [Compliance & Export Controls](#12-compliance--export-controls)
13. [System Profiling](#13-system-profiling)
14. [Metal / GPU Profiling](#14-metal--gpu-profiling)
15. [Recommendations Engine](#15-recommendations-engine)
16. [OpenTelemetry Integration](#16-opentelemetry-integration)
17. [On-Device Persistence](#17-on-device-persistence)
18. [Session Management](#18-session-management)
19. [Metrics](#19-metrics)
20. [Telemetry Schema (terra.v1)](#20-telemetry-schema-terrav1)
21. [Trace Viewer macOS App](#21-trace-viewer-macos-app)
22. [CLI Tool](#22-cli-tool)
23. [OpenClaw Integration](#23-openclaw-integration)
24. [HTTP Proxy Instrumentation](#24-http-proxy-instrumentation)
25. [Platform Support](#25-platform-support)

---

## 1. Three-Tier Integration Model

Terra offers three progressively more detailed integration tiers:

### Tier 1: Zero-Code Auto-Instrumentation

```swift
import Terra

try Terra.installOpenTelemetry(.init(
  persistence: .init(storageURL: Terra.defaultPersistenceStorageURL())
))
Terra.install(.init(privacy: .default))
try Terra.start()
```

A single `Terra.start()` call automatically instruments CoreML predictions and HTTP requests to known AI API hosts. No code changes needed in application logic.

### Tier 2: @Traced Macro

```swift
@Traced(model: "llama-3.2-1B")
func generate(prompt: String, maxTokens: Int = 512) async throws -> String {
    // your inference code
}
```

The `@Traced` macro wraps any async function in an inference span. It auto-detects common parameter names (`prompt`, `input`, `query`, `text` for prompt; `maxTokens`, `maxOutputTokens` for token limits) and forwards them to the span. Requires only the `model` argument.

**Constraints:** Async functions only. Generates a `Terra.withInferenceSpan` wrapper at compile time via SwiftSyntax.

### Tier 3: Closure-Based Wrappers

```swift
let result = try await Terra.withInferenceSpan(
    .init(model: "llama-3.2-1B", prompt: prompt, maxOutputTokens: 256)
) { scope in
    let output = try await myModel.generate(prompt)
    scope.setAttributes(["custom.key": .string("value")])
    return output
}
```

Full control over span lifecycle, attributes, events, and error recording via typed `Scope<Kind>` wrappers.

---

## 2. Span Types & Instrumentation

Terra defines 8 canonical span types:

| Span Name | Method | Purpose |
|-----------|--------|---------|
| `terra.inference` | `withInferenceSpan(_:_:)` | Model inference requests |
| `terra.model.load` | `withModelLoadSpan(...)` | Model loading operations |
| `terra.stage.prompt_eval` | `withInferenceStageSpan(.promptEval, ...)` | Prompt evaluation sub-stage |
| `terra.stage.decode` | `withInferenceStageSpan(.decode, ...)` | Token decoding sub-stage |
| `terra.stream.lifecycle` | `withInferenceStageSpan(.streamLifecycle, ...)` | Stream metadata |
| `terra.embeddings` | `withEmbeddingSpan(_:_:)` | Embedding generation |
| `terra.agent` | `withAgentInvocationSpan(agent:_:)` | Agent invocation with delegation |
| `terra.tool` | `withToolExecutionSpan(tool:call:_:)` | Tool/function call execution |
| `terra.safety_check` | `withSafetyCheckSpan(_:_:)` | Safety/moderation checks |

All span methods are async, support structured concurrency, and propagate errors. Each returns a typed `Scope<Kind>` that prevents misuse (e.g., you can't accidentally call streaming methods on a non-streaming scope).

---

## 3. Runtime Support

Terra identifies and classifies 8 ML runtime environments:

| Runtime | Key | Description |
|---------|-----|-------------|
| CoreML | `coreml` | Apple CoreML framework |
| Foundation Models | `foundation_models` | Apple Foundation Models (macOS 26+) |
| MLX | `mlx` | MLX-swift framework |
| Ollama | `ollama` | Ollama local server |
| LM Studio | `lm_studio` | LM Studio local server |
| llama.cpp | `llama_cpp` | llama.cpp C/C++ engine |
| OpenClaw Gateway | `openclaw_gateway` | OpenClaw proxy gateway |
| HTTP API | `http_api` | Remote AI APIs (OpenAI, Anthropic, Google, etc.) |

Runtime detection is automatic for HTTP-based providers using a multi-signal heuristic (host, port, path, headers, response shape) with a confidence score from 0.0 to 1.0.

---

## 4. Auto-Instrumentation: CoreML

**Module:** `TerraCoreML`

Transparent instrumentation of all CoreML predictions via Objective-C runtime method swizzling.

### What's hooked
- `MLModel.prediction(from:)` — basic predictions
- `MLModel.prediction(from:options:)` — predictions with options

### What's captured per prediction
- **Timing:** Monotonic duration via `ContinuousClock` (nanosecond precision, immune to NTP drift)
- **Compute units:** Maps `MLComputeUnits` → `"all"`, `"cpu_only"`, `"cpu_and_gpu"`, `"cpu_and_ane"`
- **Model name:** Resolved from creator-defined metadata → display name → `"unknown_coreml_model"`
- **Memory delta:** Resident memory change during prediction (via `TerraSystemProfiler`)
- **GPU metrics:** Compute time (via `TerraMetalProfiler`, if installed)
- **Error status:** Captures failure with localized description

### Deduplication
Checks `OpenTelemetry.instance.contextProvider.activeSpan` before creating a new span. If a Terra span is already active, the prediction runs uninstrumented to avoid double-tracing.

### Configuration
```swift
CoreMLInstrumentation.install(.init(
    excludedModelNames: ["fast-classifier"]  // skip low-latency models
))
```

---

## 5. Auto-Instrumentation: HTTP AI APIs

**Module:** `TerraHTTPInstrument`

Automatic instrumentation of URLSession requests to AI providers. No swizzling — uses OpenTelemetry's `URLSessionInstrumentation` callback-based API.

### Recognized providers
OpenAI, Anthropic, Google (Generative Language), Together.ai, Mistral, Groq, Cohere, Fireworks.ai, plus local servers (Ollama on port 11434, LM Studio on port 1234).

### What's captured

**From request body (JSON):**
- `gen_ai.request.model` — model name
- `gen_ai.request.max_tokens` — max output tokens (tries `max_tokens`, `max_completion_tokens`, `max_new_tokens`)
- `gen_ai.request.temperature` — sampling temperature
- `gen_ai.request.stream` — streaming flag

**From response body (JSON):**
- `gen_ai.response.model` — actual model used
- `gen_ai.usage.input_tokens` — prompt tokens (tries OpenAI, Anthropic, and Ollama field names)
- `gen_ai.usage.output_tokens` — completion tokens

**From streaming responses (SSE / NDJSON):**
- Time to first token (TTFT)
- Tokens per second
- Chunk count
- Per-stage durations (prompt eval, decode, model load)
- Stall detection (gap >= 300ms triggers `terra.stalled_token_event`)
- Inter-token gap tracking

### Runtime classification heuristic
Scores evidence from host, port, path, headers (`X-Terra-Runtime`, `X-Runtime`), model name, response keys, and content type. Normalizes to a confidence score clamped between 0.2 and 1.0, with ambiguity detection when margin between top candidates is < 0.2.

### Safety
- Max 10 MiB request/response body parsing
- No prompt or completion text captured — only structured metadata (model names, token counts, latencies)
- 256K character buffer limit for streaming recovery

---

## 6. Foundation Models Integration

**Module:** `TerraFoundationModels`

Wraps Apple's `LanguageModelSession` (macOS 26.0+, iOS 26.0+) with traced equivalents.

### API

```swift
let session = TerraTracedSession(model: .default, modelIdentifier: "apple/foundation-model")

// Simple text response
let text = try await session.respond(to: "Hello")

// Structured output (any @Generable type)
let result = try await session.respond(to: "Classify this", generating: Classification.self)

// Streaming
for try await chunk in session.streamResponse(to: "Tell me a story") {
    print(chunk)
}
```

### What's captured
- Input/output token counts (extracted via reflection-based introspection)
- Context window token count
- End-to-end latency
- Streaming: TTFT, tokens per second, chunk count
- Structured output: response type name (`terra.foundation_models.response_type`)

### Token extraction
Uses Mirror reflection to search response objects for known field names (`inputTokenCount`, `promptTokens`, `usage.prompt_tokens`, etc.) with nested extraction into `usage`, `tokenUsage`, `metrics`, and `statistics` sub-objects. Validates non-negative integers. Does not infer token counts from text length.

### Privacy
Respects Terra's content capture policies. Each method accepts a `promptCapture: CaptureIntent` parameter for per-request opt-in.

---

## 7. MLX Integration

**Module:** `TerraMLX`

User-owned generation wrapped in Terra spans. Non-invasive — no hooks into MLX framework internals.

### API

```swift
let result = try await TerraMLX.traced(
    model: "mlx-community/Llama-3.2-1B",
    maxTokens: 256,
    temperature: 0.7,
    device: "gpu",
    memoryFootprintMB: 1200.0,
    modelLoadDurationMS: 340.0
) {
    try await myMLXModel.generate(prompt)
}

// In your token callback:
TerraMLX.recordFirstToken()       // call when first token arrives
TerraMLX.recordTokenCount(42)     // call with running token count
```

### MLX-specific attributes
- `terra.mlx.device` — device type (gpu, cpu, etc.)
- `terra.mlx.memory_footprint_mb` — peak memory usage
- `terra.mlx.model_load_duration_ms` — model load time

### Design
The user retains full control of MLX-swift generation code. Terra only wraps the execution in a tracing span. Token counting and first-token events require explicit user callbacks via `recordTokenCount()` and `recordFirstToken()`.

---

## 8. llama.cpp Integration

**Module:** `TerraLlama`

Full C interop integration with llama.cpp via a handle-based callback bridge.

### Swift API

```swift
// High-level traced wrapper
let result = try await TerraLlama.traced(model: "llama-3.2", prompt: "Hello") {
    try await llamaGenerate()
}

// Or with registered scope for C callbacks
let handle = try await TerraLlama.withRegisteredScope(model: "llama-3.2", prompt: "Hello") { scope, handle in
    // pass handle to C code
    llama_generate_with_terra(handle, prompt)
}
```

### C API (for llama.cpp integration)

```c
#include "TerraLlamaHooks.h"

// Record individual token with timing
terra_llama_record_token_event(handle, token_index, decode_latency_ms, logprob, kv_cache_pct);

// Record stage transitions
terra_llama_record_stage_event(handle, TERRA_LLAMA_STAGE_DECODE, duration_ms, token_count);

// Record generation stalls
terra_llama_record_stall_event(handle, gap_ms, threshold_ms, baseline_tps);

// Finish streaming
terra_llama_finish_stream(handle);
```

### Callback bridge
Thread-safe handle-to-scope mapping via `LlamaCallbackBridge` (NSLock protected). C code receives a `uint64_t` handle and calls `@_cdecl` exported Swift functions that route through the bridge to the correct `StreamingInferenceScope`.

### What's captured
- Per-token: decode latency, log probability, KV cache usage percentage
- Per-stage: model load, prompt eval, decode, stream lifecycle, finish (with duration and token count)
- Stall detection: gap duration, threshold, baseline tokens/sec
- Layer-level metrics: per-layer name, duration, memory
- Decode stats: tokens/sec, TTFT, KV cache usage

---

## 9. Accelerate Framework Integration

**Module:** `TerraAccelerate`

Lightweight attribute builder for Apple Accelerate framework operations.

```swift
let attrs = TerraAccelerate.attributes(
    backend: "vDSP",
    operation: "fft_forward",
    durationMS: 12.5
)
```

Produces standardized attributes: `accelerate.backend`, `accelerate.operation`, `accelerate.duration_ms`. Designed to be attached to user-created spans wrapping Accelerate calls.

---

## 10. Streaming Inference

Terra provides first-class streaming support through `StreamingInferenceScope`:

```swift
try await Terra.withStreamingInferenceSpan(request) { streamScope in
    for try await token in myStream {
        streamScope.recordToken()           // increments token count, detects first token
        streamScope.recordChunk()           // increments chunk count
    }
}
```

### Streaming metrics captured
| Metric | Description |
|--------|-------------|
| `terra.latency.ttft_ms` | Time to first token |
| `terra.stream.tokens_per_second` | Decode throughput |
| `terra.stream.output_tokens` | Total output tokens |
| `terra.stream.chunk_count` | Total chunks received |
| `terra.latency.e2e_ms` | End-to-end duration |
| `terra.latency.prompt_eval_ms` | Prompt evaluation duration |
| `terra.latency.decode_ms` | Decode phase duration |

### Advanced streaming APIs
- `recordTokenLifecycle(emittedAt:decodedAt:flushedAt:)` — fine-grained token timing with nanosecond precision
- `recordPromptEval(durationMS:tokenCount:)` — prompt evaluation phase metrics
- `recordDecodeStep(tokenIndex:latencyMS:)` — individual decode step tracking
- `recordStallDetected(gapMS:thresholdMS:)` — generation stall events
- `recordOutputTokenCount(_:)` — explicit total token count from provider

### Token lifecycle policy
Configurable sampling and budgets:
- `sampleEveryN` — sample every Nth token (default: every token)
- `maxEventsPerSpan` — budget cap (default: 2000 events per span)

---

## 11. Privacy & Content Control

Terra is privacy-first. No content is captured by default.

### Content Policy

| Policy | Behavior |
|--------|----------|
| `.never` (default) | Never capture prompt/completion/thinking text |
| `.optIn` | Capture only when request explicitly opts in via `CaptureIntent.optIn` |
| `.always` | Always capture content |

### Redaction Strategy

| Strategy | Behavior |
|----------|----------|
| `.drop` | Silently remove excluded content |
| `.lengthOnly` | Replace with character count |
| `.hashSHA256` (default) | Replace with anonymized SHA-256 hash |

### Anonymization
- HMAC-SHA256 hashing with rotating keys
- Configurable rotation window (default: 24 hours)
- Per-purpose secrets prevent cross-correlation
- Key ID attached to spans for audit trail

### Per-request capture intent
Each span method accepts a `CaptureIntent` parameter (`.default` or `.optIn`) allowing individual requests to override the global policy when the policy is set to `.optIn`.

### What's protected
- System prompts
- User prompts
- Completion text
- Thinking/reasoning text
- Agent delegation prompts
- Tool inputs and outputs
- Safety check subjects

---

## 12. Compliance & Export Controls

### Export control policy
Restrict which runtimes can emit telemetry:
```swift
let compliance = CompliancePolicy(
    exportControl: .init(
        allowedRuntimes: [.coreML, .foundationModels],
        blockOnViolation: true  // or false to annotate-only
    )
)
```

When `blockOnViolation` is true, spans from disallowed runtimes are suppressed (replaced with no-op spans). When false, spans are annotated with `terra.policy.blocked` and `terra.policy.reason` attributes.

### Retention policy
```swift
let retention = RetentionPolicy(
    maxAge: .days(7),
    maxStorageSizeBytes: 256 * 1024 * 1024,  // 256 MB
    evictionMode: .oldestFirst                // or .leastRecentlyUsed
)
```

### Audit logging
- Records policy violations, schema rejections, and version mismatches
- Buffered in-memory (max 1,024 events)
- Each event: level (info/warning/error), message, timestamp, attributes
- Cross-process consent boundary prevents telemetry leaking across security contexts

---

## 13. System Profiling

**Module:** `TerraSystemProfiler`

Opt-in system-level metrics using Darwin/Mach APIs.

### Memory profiling
Captures point-in-time snapshots of process memory via `mach_task_basic_info`:
- `terra.process.memory_resident_delta_mb` — change in resident memory during a span
- `terra.process.memory_peak_mb` — peak resident memory (high-water mark)

Used automatically by `Terra.withInferenceSpan` and `CoreMLInstrumentation` when enabled.

### Thread profiling
- `ThreadProfiler.capture()` — returns current active thread count via `task_threads()` Mach API
- Fallback to `ProcessInfo.activeProcessorCount` on non-Darwin platforms

### Thermal state
- `terra.process.thermal_state` — current thermal pressure label
- Automatically attached to spans when available

### Neural Engine (experimental)
- Infrastructure stub for future Apple Neural Engine metrics
- Gated behind `TERRA_EXPERIMENTAL_ANE_PROBE=1` environment variable
- Placeholder for ANE compute, memory, and utilization metrics

---

## 14. Metal / GPU Profiling

**Module:** `TerraMetalProfiler`

Opt-in GPU performance metrics for Metal-accelerated inference.

### Captured metrics
| Attribute | Description |
|-----------|-------------|
| `metal.gpu_utilization` | GPU utilization percentage |
| `metal.memory_in_flight_mb` | In-flight GPU memory in MB |
| `metal.compute_time_ms` | GPU compute duration in ms |

### Usage
```swift
TerraMetalProfiler.install()

// Automatic: CoreMLInstrumentation attaches GPU metrics when Metal is in use
// Manual: attach to any span
let attrs = TerraMetalProfiler.attributes(
    gpuUtilization: 0.85,
    memoryInFlightMB: 512.0,
    computeTimeMS: 45.2
)
scope.setAttributes(attrs)
```

Zero overhead when not installed — guarded by boolean flag.

---

## 15. Recommendations Engine

Terra includes a built-in recommendation system that surfaces performance and behavioral suggestions.

### Recommendation kinds
| Kind | Description |
|------|-------------|
| `thermalSlowdown` | Device thermal throttling detected |
| `promptCacheMiss` | Prompt cache miss impacting latency |
| `modelSwapRegression` | Performance regression after model change |
| `stalledToken` | Token generation stall detected |
| `custom` | User-defined recommendation |

### Configuration
- **Minimum confidence threshold** (default: 0.55) — recommendations below this are dropped
- **Cooldown window** (default: 5 seconds) — suppress duplicate recommendations
- **Deduplication window** (default: 60 seconds) — per-ID dedup tracking
- **Max tracked IDs** — bounded cardinality

### Delivery
Recommendations are delivered via an async `RecommendationSink` callback:
```swift
Terra.install(.init(
    recommendationSink: { recommendation in
        print("Suggestion: \(recommendation.action) — \(recommendation.reason)")
    }
))
```

Each recommendation includes: kind, confidence (0-1), suggested action, reason, and optional metadata attributes.

---

## 16. OpenTelemetry Integration

Terra is built entirely on OpenTelemetry Swift and supports full interop with the OTel ecosystem.

### One-line setup
```swift
try Terra.installOpenTelemetry(.init(
    tracesEndpoint: URL(string: "http://localhost:4318/v1/traces")!,
    metricsEndpoint: URL(string: "http://localhost:4318/v1/metrics")!,
    enableLogs: true,
    enableSignposts: true,     // Instruments.app integration
    enableSessions: true,      // automatic session context
    samplingRatio: 1.0,        // 0.0 to 1.0
    persistence: .init(storageURL: ...)
))
```

### Provider strategies
- `registerNew` — create fresh tracer/meter/logger providers and register globally
- `augmentExisting` — merge with existing global providers (for apps already using OTel)

### Span processors
Terra registers two custom processors:
1. **TerraSpanEnrichmentProcessor** — adds privacy policy, schema version, redaction strategy, and anonymization key ID to every Terra span
2. **TerraSessionSpanProcessor** — attaches session ID and previous session ID (only to Terra spans, identified by span name prefix)

### Instruments integration
When `enableSignposts` is true, spans are mirrored to OS signposts for visualization in Instruments.app.

---

## 17. On-Device Persistence

Optional offline buffering for network-unreliable scenarios.

```swift
let config = PersistenceConfiguration(
    storageURL: Terra.defaultPersistenceStorageURL(),
    performancePreset: .reliability  // or .bandwidth
)
```

### Default storage paths
- Traces: `~/.cache/opentelemetry/terra/traces/`
- Metrics: `~/.cache/opentelemetry/terra/metrics/`
- Logs: `~/.cache/opentelemetry/terra/logs/`

### Behavior
- Wraps OTLP exporters with `PersistenceSpanExporter` / `PersistenceMetricExporter`
- Spans are written to disk when network is unavailable
- Automatically replayed when connectivity is restored
- Subject to retention policy (max age, max size, eviction mode)

---

## 18. Session Management

Automatic session context for grouping related spans.

- Session ID generated per app launch
- Previous session ID tracked for continuity analysis
- Attached to all Terra spans via `TerraSessionSpanProcessor`
- Available as `terra.session.id` and `terra.session.previous_id` attributes

---

## 19. Metrics

Terra emits 5 OpenTelemetry metric instruments:

| Metric | Type | Description |
|--------|------|-------------|
| `terra.inference.count` | Counter | Total inference operations |
| `terra.inference.duration_ms` | Histogram | Inference duration distribution |
| `terra.recommendation.count` | Counter | Recommendations surfaced |
| `terra.anomaly.count` | Counter | Anomalies detected |
| `terra.stall.count` | Counter | Token generation stalls |

Metrics are exported via OTLP/HTTP with configurable export intervals.

---

## 20. Telemetry Schema (terra.v1)

All Terra telemetry follows the `terra.v1` contract.

### Required contract attributes (every span)
- `terra.semantic.version` — schema version (`v1`)
- `terra.schema.family` — must be `terra`
- `terra.runtime` — one of the 8 supported runtimes
- `terra.request.id` — unique per-request UUID
- `terra.session.id` — session identifier
- `terra.model.fingerprint` — pipe-delimited model identity (`model=X|runtime=Y|quant=Z|...`)

### Model fingerprint encoding
```
model=llama-3.2-1B|runtime=coreml|quant=q4_0|tokenizer=v2|backend=ane
```

### Attribute namespaces
- `gen_ai.*` — OpenTelemetry GenAI semantic conventions (operation name, model, tokens, temperature, finish reason)
- `terra.*` — Terra-specific attributes (runtime, streaming, latency, privacy, compliance, hardware)
- `terra.content.*` — Privacy-governed content attributes (prompt, completion, thinking)
- `terra.hw.*` — Hardware telemetry (RSS, GPU occupancy, ANE utilization)
- `terra.stream.*` — Streaming metrics (TTFT, TPS, chunks, output tokens)
- `terra.latency.*` — Timing metrics (e2e, ttft, prompt eval, decode, model load)
- `terra.policy.*` — Compliance annotations (blocked, reason)

### Contract validation
The OTLP decoder (`OTLPDecoder`) validates all incoming spans against the terra.v1 contract. Spans missing required attributes are rejected with `TelemetryContractViolation` errors.

---

## 21. Trace Viewer macOS App

**Module:** `TraceMacApp` / `TraceMacAppUI`

A native macOS application for viewing and analyzing Terra traces.

### Three-column layout
1. **Trace list** — filterable/sortable list of captured traces with runtime badges, connection status, and search
2. **Content area** — toggles between tree view (hierarchical span visualization) and timeline view (horizontal canvas with zoom)
3. **Detail panel** — tabbed span inspector with attributes, events, and links

### Data sources
- **File system** — loads traces from `~/.cache/opentelemetry/terra/traces/` (or custom directory)
- **OTLP receiver** — built-in HTTP server on port 4318 for live ingestion
- **Ollama logs** — parses Ollama log files into trace format
- **File watcher** — monitors trace directory for automatic reload

### Filtering and sorting
- Runtime filter (CoreML, Ollama, MLX, LM Studio, llama.cpp, OpenClaw, HTTP API)
- Error-only filter
- Text search (trace ID, display name, hex string)
- Sort: newest, oldest, duration ascending/descending
- OpenClaw source filter (gateway/diagnostics/all)

### Timeline visualization
- Canvas-based rendering for performance
- Spans packed into non-overlapping lanes
- Critical span markers (> 5s duration)
- Zoom and pan support
- Click-to-select span hit testing
- Event markers on timeline

### Span tree visualization
- Hierarchical tree layout with parent-child nesting
- Layout engine calculates positioning
- Edge rendering between nodes
- Color-coded by runtime

### Dashboard metrics
- Latency percentiles (p50, p95, p99)
- LLM-specific metrics (TTFT, E2E, prompt eval, decode timing)
- Anomaly and stall counts
- Recommendation count
- Runtime distribution breakdown

### Span inspector
- **Attributes tab** — sorted key-value table of all span attributes
- **Events tab** — classified by category:
  - Lifecycle events (token/stream lifecycle)
  - Policy events (audit, compliance)
  - Hardware events (process, thermal, memory)
  - Recommendation events
  - Anomaly events
- **Links tab** — cross-trace span references
- **Raw tab** — raw JSON representation

### Live mode
Auto-selects newest trace every 2 seconds. Detects new traces via `knownTraceIDs` tracking.

### Infrastructure
- `AppState` (`@Observable`, `@MainActor`) — single source of truth
- `AppCoordinator` — NSWindow management, toolbar, menu actions
- License-gated features (file watcher, diagnostics export)
- Diagnostics export for support
- Onboarding and quickstart windows

---

## 22. CLI Tool

**Module:** `TerraCLI` (binary: `terra`)

Command-line trace receiver and renderer.

### `terra trace serve`
Starts an OTLP/HTTP server and renders traces in real-time.

```bash
terra trace serve                          # stream format, localhost:4318
terra trace serve --format tree            # hierarchical tree output
terra trace serve --bind-all --port 4318   # accept from devices on LAN
terra trace serve --filter name=terra.inference  # filter by span name prefix
terra trace serve --filter trace=abc123...       # filter by 32-char trace ID
```

**Output formats:**
- **Stream** — one span per line with timestamp, duration, name, trace/span IDs, attributes
- **Tree** — periodically refreshed hierarchical view with ASCII art branches (configurable cadence via `--print-every`)

### `terra trace doctor`
Diagnostic checklist for common setup issues (endpoint configuration, ATS, local network permissions, LAN connectivity).

### `terra trace print` (scaffold)
Load and render traces from saved OTLP protobuf or JSONL files. Currently scaffolded, not yet implemented.

---

## 23. OpenClaw Integration

Terra integrates with OpenClaw, a transparent AI API proxy.

### Modes
| Mode | Description |
|------|-------------|
| `.disabled` | No OpenClaw integration |
| `.diagnosticsOnly` | Export spans as JSONL for dashboard analysis |
| `.gatewayOnly` | Instrument gateway HTTP requests |
| `.dualPath` | Both diagnostics and gateway instrumentation |

### Configuration
- Gateway hosts and base URL
- Authentication: none or bearer token
- Diagnostics export directory
- Transparent proxy mode (system-level packet capture)
- Plugin installation via `openclaw` CLI

### In the Trace Viewer
- Source filter: gateway traces, diagnostics traces, or all
- Connection status indicator
- Setup accessible from filter menu

---

## 24. HTTP Proxy Instrumentation

**Module:** `TerraAutoInstrument`

Transparent HTTP proxy for instrumenting local AI servers.

### How it works
- Registers a `URLProtocol` subclass
- Intercepts requests to a configured `listenHost:listenPort`
- Forwards to an upstream server (e.g., Ollama at 127.0.0.1:11434)
- Marks forwarded traffic with `X-Terra-Proxy: active` header to prevent loops

### Use cases
- Ollama (default port 11434)
- LM Studio (default port 1234)
- Any local inference server

---

## 25. Platform Support

| Platform | Minimum Version |
|----------|----------------|
| macOS | 14.0 |
| iOS | 13.0 |
| tvOS | 13.0 |
| watchOS | 6.0 |
| visionOS | 1.0 |

**Swift version:** 5.9+
**Swift tools version:** 5.9

### Conditional compilation
Modules that depend on platform-specific frameworks use `#if canImport(...)` guards:
- `CoreML` — `TerraCoreML` provides empty stub on unsupported platforms
- `FoundationModels` — `TerraFoundationModels` requires macOS 26.0+ / iOS 26.0+
- `Metal` — `TerraMetalProfiler` gracefully degrades
- Darwin/Mach APIs — `TerraSystemProfiler` falls back to `ProcessInfo` on non-Darwin
