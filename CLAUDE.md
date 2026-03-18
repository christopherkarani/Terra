# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Terra is an on-device GenAI observability SDK for Swift, built on OpenTelemetry. It instruments model inference, embeddings, agent steps, tool calls, and safety checks across Apple platforms with privacy-first defaults.

> **Note:** The TraceMacApp viewer and TerraCLI have been extracted to the [TerraViewer](https://github.com/christopherkarani/TerraViewer) repository. TerraViewer depends on Terra via SPM for the `TerraTraceKit` library.

## Build Commands

```bash
# Build the sample app
swift build --target TerraSample

# Run all tests
swift test

# Run a single test target
swift test --filter TerraTests
swift test --filter TerraTraceKitTests

# Run a specific test by name
swift test --filter TerraTests.TestClassName/testMethodName
```

## Architecture

### Module Dependency Graph

```
Terra (umbrella — Sources/TerraAutoInstrument/)
├── TerraCore (Sources/Terra/) → TerraSystemProfiler, TerraMetalProfiler
├── TerraCoreML → TerraCore, TerraMetalProfiler, TerraSystemProfiler
├── TerraHTTPInstrument → TerraCore
├── TerraFoundationModels → TerraCore
├── TerraMLX → TerraCore
├── TerraLlama → TerraCore
├── TerraAccelerate (standalone — OTel only)
└── TerraTracedMacro (swift-syntax macro)

TerraTraceKit (standalone — no Terra dependency)
└── Trace ingestion, OTLP decoding, span storage, view models
```

All telemetry modules depend on `opentelemetry-swift-core` / `opentelemetry-swift`.

### Terra SDK — Core (`Sources/Terra/`)

The core library. Public API: `Terra.install()` for one-time setup, then `Terra.with*Span()` async wrappers. Key files:

- `Terra.swift` — Public facade: `withInferenceSpan`, `withStreamingInferenceSpan`, `withAgentInvocationSpan`, `withToolExecutionSpan`, `withEmbeddingSpan`, `withSafetyCheckSpan`. Also `StreamingInferenceScope` for streaming token telemetry (TTFT, throughput, chunk count).
- `Terra+Constants.swift` — Span names, semantic attribute keys, and metric names in `gen_ai.*` and `terra.*` namespaces.
- `Terra+Requests.swift` — Request/response models (`InferenceRequest`, `EmbeddingRequest`, `Agent`, `Tool`, `ToolCall`, `SafetyCheck`) and type-safe span marker enums.
- `Terra+Runtime.swift` — `Installation`, runtime provider overrides, privacy storage, SHA/HMAC helpers, anonymization key management, and `TerraMetrics`.
- `Terra+Privacy.swift` — `ContentPolicy` (.never/.optIn/.always), `RedactionStrategy` (.drop/.lengthOnly/.hashHMACSHA256/.hashSHA256 legacy), and `CaptureIntent` (.default/.optIn).
- `Terra+OpenTelemetry.swift` — `installOpenTelemetry()` wires up OTLP/HTTP export, persistence, signposts, sessions. `TracerProviderStrategy`: `registerNew` vs `augmentExisting`.
- `Terra+Scope.swift` — Generic `Scope<Kind>` wrapper with `addEvent`, `setAttributes`, `recordError`, and `span` escape hatch.
- `TerraSessionSpanProcessor.swift` — Injects `session.id` and `session.previousId` on Terra spans.
- `TerraSpanEnrichmentProcessor.swift` — Adds content policy, schema version, redaction strategy, anonymization key ID.

### Terra SDK — Auto-Instrumentation (`Sources/TerraAutoInstrument/`)

The umbrella `Terra` product. Entry point: `Terra.start()` (in `Terra+Start.swift`).

- `Terra+Start.swift` — Orchestrates: installs OTel providers, CoreML instrumentation, HTTP instrumentation, memory/GPU profilers, and OpenClaw diagnostics/gateway modes. Configurable via `AutoInstrumentConfiguration` and `Instrumentations`.
- Proxy instrumentation is currently a reserved configuration path (`.proxy`) and not backed by an in-repo HTTP proxy target.
- `OpenClawConfiguration.swift` — Modes: `.disabled`, `.diagnosticsOnly`, `.gatewayOnly`, `.dualPath`.

### Specialized Modules

**TerraCoreML** (`Sources/TerraCoreML/`): ObjC runtime swizzling on `MLModel.prediction(from:)` and `prediction(from:options:)`. Lock-free dedup via activeSpan check. Captures monotonic duration, compute units, model name (metadata → displayName → fallback), memory delta, GPU compute time. Configurable `excludedModelNames`.

**TerraHTTPInstrument** (`Sources/TerraHTTPInstrument/`): Uses OTel's `URLSessionInstrumentation` callbacks (no swizzling). Recognizes 8 cloud providers + Ollama/LM Studio by host/port/path. Parses request JSON (model, max_tokens, temperature, stream), response JSON (model, token counts), and streaming SSE/NDJSON (TTFT, TPS, chunks, stall detection at 300ms gaps). Runtime classification heuristic scores evidence with confidence 0.2–1.0. Max 10 MiB body parsing. `AIResponseStreamParser` is the most complex file (~850 lines).

**TerraFoundationModels** (`Sources/TerraFoundationModels/`): Wraps `LanguageModelSession` via `TerraTracedSession` (aliased as `Terra.TracedSession`). Three methods: `respond(to:)`, `respond(to:generating:)` for `@Generable`, `streamResponse(to:)`. Token extraction via Mirror reflection searching known field names in response objects. Backend protocol abstraction for testability.

**TerraMLX** (`Sources/TerraMLX/`): User-owned generation wrapped in spans. `TerraMLX.traced(model:...)` creates inference span around user closure. `recordFirstToken()` and `recordTokenCount()` use activeSpan context — no hooks into MLX internals.

**TerraLlama** (`Sources/TerraLlama/`): C interop via `@_cdecl` exported functions and `LlamaCallbackBridge` (NSLock-protected handle-to-scope map). C header `TerraLlamaHooks.h` declares `terra_llama_record_token_event`, `terra_llama_record_stage_event`, `terra_llama_record_stall_event`, `terra_llama_finish_stream`. Per-token decode latency, logprob, KV cache. Per-stage durations. Layer-level metrics.

**TerraAccelerate** (`Sources/TerraAccelerate/`): Minimal attribute builder — `attributes(backend:operation:durationMS:)`.

**@Traced Macro** (`Sources/TerraTracedMacro/` + `Sources/TerraTracedMacroPlugin/`): `@attached(body)` macro via SwiftSyntax. Auto-detects `prompt`/`input`/`query`/`text` and `maxTokens`/`maxOutputTokens` parameters. Wraps function body in `Terra.withInferenceSpan`. Async functions only.

**TerraSystemProfiler** (`Sources/TerraSystemProfiler/`): Memory snapshots via `mach_task_basic_info` (resident delta + peak). Thread count via `task_threads()`. Thermal state label. Experimental ANE probe gated behind `TERRA_EXPERIMENTAL_ANE_PROBE=1`.

**TerraMetalProfiler** (`Sources/TerraMetalProfiler/`): GPU utilization, in-flight memory, compute time. Zero overhead when not installed.

### TerraTraceKit (`Sources/TerraTraceKit/`)

Standalone trace processing library (no dependency on Terra SDK). Key files:

- `Models.swift` — `TraceID`, `SpanID`, `SpanRecord`, `TraceSnapshot`, `Attributes` (sorted collection)
- `Trace.swift` — Aggregates spans into `Trace` objects with root detection and validation
- `OTLPDecoder.swift` — Decodes OTLP protobuf with compressed/decompressed size limits, span/attribute budgets, and AnyValue depth guards.
- `OTLPHTTPServer.swift` — HTTP/1.1 server on port 4318 with header/body read deadlines, bounded active connections, and decode-task cancellation on disconnect.
- `TraceStore.swift` — Actor-based in-memory span storage (10k default, LRU eviction, dedup by traceID+spanID)
- `TraceLoader.swift` — File discovery from `~/.cache/opentelemetry/terra/traces/` + decoding
- `TerraTelemetryClassifier.swift` — Event categories: lifecycle, policy, hardware, recommendations, anomalies
- View models: `TimelineViewModel` (lane packing, critical >5s), `SpanDetailViewModel` (attribute/event extraction), `TraceListViewModel` (filtering/sorting)
- `Renderers.swift` — `StreamRenderer` (one-line) and `TreeRenderer` (ASCII hierarchy) for CLI

## Testing

8 test targets under `Tests/`:
- `TerraTests` (13 files), `TerraTraceKitTests` (10 files)
- `TerraAutoInstrumentTests`, `TerraCoreMLTests`, `TerraFoundationModelsTests`
- `TerraHTTPInstrumentTests` (6 files), `TerraMLXTests`, `TerraTracedMacroTests`

Tests are a mix of `swift-testing` and XCTest, with `InMemoryExporter` used for span verification.

## CI

GitHub Actions (`.github/workflows/ci.yml`):
- **swift job**: SPM build + tests, SwiftLint, API compatibility checks
- SwiftLint is installed at a pinned version from GitHub releases.

## Key Conventions

- Platform: macOS 14+, iOS 13+, tvOS 13+, watchOS 6+, visionOS 1+. Swift 5.9, swift-tools-version 5.9
- Span names align with GenAI semantic conventions (`gen_ai.*`) plus Terra-specific namespaces where required.
- All attribute keys use `terra.*` or `gen_ai.*` namespaces (defined in `Terra+Constants.swift` `Keys`)
- Privacy enforced at install time: `ContentPolicy` (`.never` default) and keyed redaction (`.hashHMACSHA256` default strategy).
- `ContinuousClock` for all timing (monotonic, immune to NTP drift)
- `Scope<Kind>` generic wrappers with empty enum markers for compile-time span type safety
- Streaming: `StreamingInferenceScope` tracks TTFT, output tokens, chunk count, and derived tokens/second metrics.

## External Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| swift-protobuf | 1.25.0+ | OTLP protobuf serialization |
| opentelemetry-swift-core | 2.3.0+ | OTel API & SDK |
| opentelemetry-swift | 2.3.0+ | OTel exporters & integrations |
| swift-crypto | 4.2.0+ | HMAC-SHA256 for anonymization |
| swift-testing | 0.99.0+ | Test framework |
| swift-syntax | 600.0.0+ | @Traced macro |

## Documentation

- `Docs/api-reference.md` — Full public API surface
- `Docs/cookbook.md` — Copy-paste recipes and advanced patterns
- `Docs/integrations.md` — CoreML, FoundationModels, MLX, llama.cpp integration
- `Docs/migration.md` — Legacy to current API migration
