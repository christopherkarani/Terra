# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Terra is an on-device GenAI observability SDK for Swift, built on OpenTelemetry. It instruments model inference, embeddings, agent steps, tool calls, and safety checks across Apple platforms with privacy-first defaults.

## Build Commands

### SPM (primary for development)

```bash
# Build the macOS app
swift build --target TraceMacApp

# Build and launch
pkill -f TraceMacApp; swift build --target TraceMacApp && open .build/arm64-apple-macosx/debug/TraceMacApp

# Build the CLI tool
swift build --target terra

# Build the sample app
swift build --target TerraSample

# Run all tests
swift test

# Run a single test target
swift test --filter TerraTests
swift test --filter TerraTraceKitTests
swift test --filter TraceMacAppTests

# Run a specific test by name
swift test --filter TerraTests.TestClassName/testMethodName
```

### Xcode project (release builds / signing only)

Located at `Apps/TraceMacApp/TraceMacApp.xcodeproj`. Only used for signed releases; does **not** include SwiftUI views from subdirectories. See "Dual Build System" below.

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

TraceMacApp (executable) → TraceMacAppUI + TerraTraceKit
TerraCLI (executable) → TerraTraceKit + swift-argument-parser
```

All telemetry modules depend on `opentelemetry-swift-core` / `opentelemetry-swift`.

### Terra SDK — Core (`Sources/Terra/`)

The core library. Public API: `Terra.install()` for one-time setup, then `Terra.with*Span()` async wrappers. Key files:

- `Terra.swift` — Public facade: `withInferenceSpan`, `withModelLoadSpan`, `withStreamingInferenceSpan`, `withAgentInvocationSpan`, `withToolExecutionSpan`, `withEmbeddingSpan`, `withSafetyCheckSpan`. Also `StreamingInferenceScope` for streaming token telemetry (TTFT, TPS, stall detection).
- `Terra+Constants.swift` — `SpanNames` (9 canonical names), `Keys` (80+ attribute keys in `gen_ai.*` and `terra.*` namespaces), `RuntimeKind` (8 runtimes), `MetricNames` (5 metrics). This is the single source of truth for the semantic schema.
- `Terra+Requests.swift` — Request/response models: `InferenceRequest`, `ModelFingerprint` (pipe-delimited `model=X|runtime=Y|quant=Z`), `EmbeddingRequest`, `Agent`, `Tool`, `ToolCall`, `SafetyCheck`, `Recommendation`. Type-safe span markers via empty enums (`InferenceSpan`, `ModelLoadSpan`, etc.).
- `Terra+Runtime.swift` — `TelemetryConfiguration` (token lifecycle policy, recommendation policy, kill switches), `Installation` (privacy + compliance + telemetry config), `Runtime` singleton (session ID, audit buffer, recommendation dedup, SHA256/HMAC crypto). `TerraMetrics` for OTel counters/histograms.
- `Terra+Privacy.swift` — `ContentPolicy` (.never/.optIn/.always), `RedactionStrategy` (.drop/.lengthOnly/.hashSHA256), `AnonymizationPolicy` (HMAC rotating keys, 24h default), `CompliancePolicy` (export control with runtime whitelist, retention with max age/size/eviction, audit events), `CaptureIntent` (.default/.optIn).
- `Terra+OpenTelemetry.swift` — `installOpenTelemetry()` wires up OTLP/HTTP export, persistence, signposts, sessions. `TracerProviderStrategy`: `registerNew` vs `augmentExisting`.
- `Terra+Scope.swift` — Generic `Scope<Kind>` wrapper with `addEvent`, `setAttributes`, `recordError`, and `span` escape hatch.
- `TerraSessionSpanProcessor.swift` — Injects `session.id` and `session.previousId` on Terra spans.
- `TerraSpanEnrichmentProcessor.swift` — Adds content policy, schema version, redaction strategy, anonymization key ID.

### Terra SDK — Auto-Instrumentation (`Sources/TerraAutoInstrument/`)

The umbrella `Terra` product. Entry point: `Terra.start()` (in `Terra+Start.swift`).

- `Terra+Start.swift` — Orchestrates: installs OTel providers, CoreML swizzling, HTTP instrumentation, memory/GPU profilers, proxy, OpenClaw. Configurable via `AutoInstrumentConfiguration` with `.coreML`, `.httpAIAPIs`, `.proxy`, `.openClawGateway`, `.openClawDiagnostics` option set.
- `TerraHTTPProxy.swift` — `URLProtocol` subclass that intercepts requests to `listenHost:listenPort`, forwards to upstream (Ollama 11434, LM Studio 1234). Uses `X-Terra-Proxy: active` header to prevent loops.
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
- `OTLPDecoder.swift` — Decodes OTLP protobuf with terra.v1 contract validation (required: semantic version, schema family, runtime, request ID, session ID, model fingerprint)
- `OTLPHTTPServer.swift` — HTTP/1.1 server on port 4318 with runtime allowlist, gzip/deflate decompression, audit events
- `TraceStore.swift` — Actor-based in-memory span storage (10k default, LRU eviction, dedup by traceID+spanID)
- `TraceLoader.swift` — File discovery from `~/.cache/opentelemetry/terra/traces/` + decoding
- `TerraTelemetryClassifier.swift` — Event categories: lifecycle, policy, hardware, recommendations, anomalies
- View models: `TimelineViewModel` (lane packing, critical >5s), `SpanDetailViewModel` (attribute/event extraction), `TraceListViewModel` (filtering/sorting)
- `Renderers.swift` — `StreamRenderer` (one-line) and `TreeRenderer` (ASCII hierarchy) for CLI

### TraceMacApp (`Sources/TraceMacApp/`)

macOS trace viewer. Entry: `TraceMacAppMain` → `TraceMacAppDelegate` → `AppCoordinator` → SwiftUI `DashboardView`.

**Data flow:** `AppState` (`@Observable`, `@MainActor`) is the single source of truth, injected via `@Environment`. Loads traces via `TraceLoader` and/or OTLP receiver. Supports file watching, live mode (auto-select newest trace every 2s), Ollama log ingestion, OpenClaw gateway/diagnostics.

**Three-column layout:**
1. **Trace list** — `TraceListView` with runtime filter bar, connection status, search
2. **Content** — `TraceTreeView` (hierarchical with layout engine) or `TraceTimelineCanvasView` (Canvas-based, non-overlapping lanes, zoom/pan)
3. **Detail** — `SpanDetailView` with tabs: attributes, events (classified), links, raw JSON

**Key files:**
- `AppCoordinator.swift` — NSWindow, toolbar, menus, license integration, onboarding
- `ViewModels/AppState.swift` — Central state: traces, selection, filtering, sort, OTLP receiver, file watcher, OpenClaw config, live mode
- `ViewModels/DashboardViewModel.swift` — Computed KPIs: latency percentiles, TTFT, anomaly/stall counts, runtime distribution
- `TraceRuntime.swift` — Runtime detection from span attributes, color mapping
- `Theme/DashboardTheme.swift` — Colors, fonts, spacing constants

### TerraCLI (`Sources/terra-cli/`)

Commands: `terra trace serve` (OTLP server + real-time rendering in stream/tree format), `terra trace doctor` (diagnostic checklist), `terra trace print` (scaffold, not yet implemented). Filtering by span name prefix or trace ID.

## Dual Build System

Terra has a **dual build system**: SPM (`Package.swift`) and Xcode (`Apps/TraceMacApp/TraceMacApp.xcodeproj`).

**SPM** auto-discovers all `.swift` files under `Sources/TraceMacApp/` recursively. New files are included automatically.

**Xcode project** only lists ~30 specific root-level files (AppKit controllers, licensing, infrastructure). It links only `TerraTraceKit` — not `TraceMacAppUI`. SwiftUI views from subdirectories (`TraceList/`, `Dashboard/`, `FlowGraph/`, `SpanInspector/`, `Timeline/`, `Theme/`, `TraceTree/`, `Components/`, `Commands/`) are **not** in the Xcode build.

To add files to the Xcode build, manually edit `PBXFileReference`, `PBXGroup`, and `PBXSourcesBuildPhase` in `project.pbxproj`.

## Testing

10 test targets under `Tests/`:
- `TerraTests` (13 files), `TerraTraceKitTests` (10 files), `TraceMacAppTests` (10 files), `TraceMacAppUITests` (13 files)
- `TerraAutoInstrumentTests`, `TerraCoreMLTests`, `TerraFoundationModelsTests`
- `TerraHTTPInstrumentTests` (6 files), `TerraMLXTests`, `TerraTracedMacroTests`

Tests use `swift-testing` framework with `InMemoryExporter` for span verification. Fixture data in `Tests/TerraV1/`.

## CI

GitHub Actions (`.github/workflows/ci.yml`):
- **swift job**: SPM tests, SwiftLint, API compatibility checks, unsigned Xcode build
- **rc-hardening job**: Runs `scripts/rc_hardening.sh` on dispatch/tags
- Release scripts in `scripts/release/` (build, DMG creation, notarization)

## Key Conventions

- Platform: macOS 14+, iOS 13+, tvOS 13+, watchOS 6+, visionOS 1+. Swift 5.9, swift-tools-version 5.9
- All span names use `terra.*` prefix (defined in `Terra+Constants.swift` `SpanNames`)
- All attribute keys use `terra.*` or `gen_ai.*` namespaces (defined in `Terra+Constants.swift` `Keys`)
- Privacy enforced at install time: `ContentPolicy` (.never default), `RedactionStrategy` (.hashSHA256 default). Never capture content without explicit opt-in
- `RuntimeKind` enum: coreML, foundationModels, mlx, ollama, lmStudio, llamaCpp, openClawGateway, httpAPI
- Schema version is `v1` — enforced by `OTLPDecoder` contract validation (rejects spans missing required attributes)
- `@Observable` + `@MainActor` for SwiftUI view models (no legacy `@StateObject`/`@ObservedObject`)
- `ContinuousClock` for all timing (monotonic, immune to NTP drift)
- `Scope<Kind>` generic wrappers with empty enum markers for compile-time span type safety
- Streaming: `StreamingInferenceScope` tracks TTFT, TPS, chunks, stalls. Token lifecycle policy controls sampling (`sampleEveryN`) and budget (`maxEventsPerSpan`)
- Recommendations: configurable confidence threshold (0.55), cooldown (5s), dedup window (60s)
- Model fingerprint format: `model=X|runtime=Y|quant=Z|tokenizer=W|backend=V`

## External Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| swift-argument-parser | 1.3.0+ | CLI argument parsing |
| swift-protobuf | 1.25.0+ | OTLP protobuf serialization |
| opentelemetry-swift-core | 2.3.0+ | OTel API & SDK |
| opentelemetry-swift | 2.3.0+ | OTel exporters & integrations |
| swift-crypto | 4.2.0+ | HMAC-SHA256 for anonymization |
| swift-testing | 0.99.0+ | Test framework |
| swift-syntax | 600.0.0+ | @Traced macro |

## Documentation

- `docs/TelemetryConvention/terra-v1.md` — Full v1 telemetry contract specification
- `docs/TERRA_FEATURES.md` — Comprehensive feature reference (all 25 features)
- `docs/terra-features.html` — Visual HTML feature page
- `AIObservabilityPlan.md` — Implementation phases and gaps
- `terra-v1-rc-production-readiness-plan.md` — Production readiness checklist
