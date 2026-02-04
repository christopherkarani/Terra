# Terra: On-Device LLM/Agent Observability on OpenTelemetry Swift

## Recommendations (Answered First)

### 1) Should You Build a Custom Runtime?
Recommendation: do **not** start by building a full custom LLM runtime unless you have a hard requirement (custom kernels, model format constraints, nonstandard quantization, etc.).

Recommended approach:
1. Define a **runtime-agnostic execution boundary** (your public API boundary), and instrument that boundary with OpenTelemetry.
2. Implement backends behind it in this order:
1. **Core ML first** (broad adoption, best Apple platform story).
2. **Metal/Accelerate adapters second** for measured hot paths or custom ops.
3. Consider a **full custom runtime** only if profiling shows it is required.

### 2) Where Should Telemetry Land?
Recommendation: ship **both** developer-first and production export.
1. **Local visibility**: Signposts so spans show up in Instruments.
2. **Production export**: OTLP (HTTP is usually simplest on-device) decorated with **persistence** for offline + restart durability.

Logs should be optional and privacy-gated; traces + metrics carry most of the value.

### 3) Should Terra Fork OpenTelemetry Swift?
Recommendation: **no fork** by default.

Terra should be a standalone framework (its own SwiftPM package/repo) that **depends on**:
1. **OpenTelemetry Swift Core** (`opentelemetry-swift-core`) for the API/SDK surface (Tracer/Span/Meter/LogRecord, context propagation).
2. **OpenTelemetry Swift** (`opentelemetry-swift`) for on-device-friendly instrumentation/exporter components (e.g. Signpost integration, OTLP exporters, persistence exporter).

Forking is reserved for a proven blocker that cannot be solved via extension points or an upstream PR.

## Plan

### Goals
1. Provide a Swift framework that instruments:
1. Model inference (prefill/decode/streaming)
2. Embeddings
3. Agent runs (planning, tool calls, memory, retrieval)
4. Safety checks
2. Export telemetry locally (Instruments) and remotely (OTLP) with offline persistence.
3. Default to privacy-safe behavior and correct Swift structured concurrency context propagation.

### Non-Goals (V1)
1. Implement a full custom LLM runtime.
2. Record raw prompts/outputs by default.
3. Cross-process distributed tracing (in-process focus first).

### Architecture Overview
1. `TerraCore`: Public API types, conventions, redaction policies.
2. `TerraOTel`: OpenTelemetry binding (tracer/meter/logger wiring, processors).
3. `TerraBackends`: Optional adapters (Core ML, Metal, Accelerate) for backend-specific metrics/attributes.
4. `TerraExport`: Turnkey install helpers for Signpost + OTLP + Persistence.

### Packaging and Dependencies (Production Shape)
1. Terra ships as a standalone SwiftPM package (recommended: its own repo).
2. Terra depends on:
1. `opentelemetry-swift-core` (required) — Terra composes the API/SDK types rather than re-implementing them.
2. `opentelemetry-swift` (required by this plan) — Terra reuses the existing on-device exporter/instrumentation modules where possible:
1. `SignPostIntegration` for Instruments visibility.
2. `OpenTelemetryProtocolExporterHttp` / `OpenTelemetryProtocolExporterGrpc` for OTLP.
3. `PersistenceExporter` for offline + restart durability.
3. Terra is “hard to misuse”:
1. Terra’s public API is runtime-agnostic and does not require customers to learn OpenTelemetry internals.
2. Advanced users can integrate Terra into an existing OTel provider setup (BYO `TracerProvider` / exporters).

### Phase 0: Repo and Package Setup
1. Create Terra as its own SwiftPM package.
1. Add new targets under `Sources/`:
1. `Terra`
2. `TerraCoreML` (optional, if first-party Core ML integration is desired)
2. Add corresponding test targets under `Tests/`.
3. Define instrumentation scope names:
1. Tracing/metrics instrumentation name: `com.yourorg.terra`
2. Version: semver tied to framework release.
4. Add dependencies:
1. `opentelemetry-swift-core` (API/SDK)
2. `opentelemetry-swift` (Signpost, OTLP exporters, persistence exporter)

### Phase 1: Semantics and Privacy Policy
1. Define a minimal semantic vocabulary:
1. Prefer GenAI semantic convention keys where applicable (`gen_ai.*`).
2. Use a stable custom prefix for Terra-specific and device/runtime details (`terra.*`).
2. Define privacy controls:
1. `ContentPolicy`: `.never`, `.optIn`, `.always`
2. Redaction pipeline: hash, length-only, allowlist keys, drop high-risk fields.
3. Define low-cardinality rules:
1. Document which fields are allowed as attributes vs span events vs logs.

Deliverable: a documented attribute key list, redaction behavior, and examples.

### Phase 2 (TDD First): Core Public API
1. Write Swift Testing tests that fail initially:
1. `withInferenceSpan` creates a span with correct name/kind/attributes.
2. Child spans inherit parent in structured tasks.
3. `Task.detached` does not inherit (document and test expected behavior).
4. Metrics are recorded even if spans are sampled out (where feasible).
2. Implement the API surface:
1. `Terra.withInferenceSpan(request) { scope in ... }`
2. `Terra.withAgentInvocationSpan(agent) { scope in ... }`
3. `Terra.withToolExecutionSpan(tool, call) { scope in ... }`
4. `Terra.withEmbeddingSpan(request) { scope in ... }`
5. `Terra.withSafetyCheckSpan(check) { scope in ... }`
3. Provide lightweight "scope" helpers:
1. `span`
2. `addEvent(_:)`
3. `recordError(_:)`
4. `setAttributes(_:)`

Deliverable: minimal, stable, hard-to-misuse public API.

### Phase 3: OpenTelemetry Wiring and Processors
1. Implement enrichment processors patterned after components in `opentelemetry-swift`:
1. `TerraSpanEnrichmentProcessor` to attach session IDs, runtime info, sampling decisions.
2. `TerraLogRecordProcessor` (optional) for structured "agent lifecycle" events.
2. Add an install helper:
1. `Terra.install(...)` that:
1. registers or integrates with existing tracer/meter/logger providers
2. installs Signpost processor in dev/debug configs
3. installs persistence-decorated OTLP exporters for production

Deliverable: one-call adoption path for apps.

### Phase 4: Backend Adapters (Recommended Order)
1. Core ML adapter (recommended first):
1. Record model identifier/version.
2. Record compute target (CPU/GPU/ANE) when known.
3. Record batch size and input-shape metadata (low-cardinality only).
2. Metal/Accelerate adapter (optional):
1. Wrap command buffer lifetimes with spans/events (opt-in).
2. Record kernel stage timings as child spans or span events.

Deliverable: backend-specific enrichment without leaking backend types into core API.

### Phase 5: Agent Instrumentation Patterns
1. Define standard span structure for agent runs:
1. `invoke_agent` span
2. child spans for planning, retrieval, tool calls, memory, safety
2. Define tool-call schema:
1. Tool name, tool type, status
2. Arguments/result capture only via redaction and explicit opt-in
3. Define correlation:
1. session ID attachment (optionally reuse `Sessions` module)
2. conversation/run IDs as non-identifying ephemeral IDs

Deliverable: consistent trace shape across agents.

### Phase 6: Export Strategy
1. Local:
1. Install `OSSignposterIntegration`/`SignPostIntegration` so spans appear in Instruments.
2. Remote:
1. OTLP HTTP exporter for traces/metrics (logs only if explicitly enabled).
2. Decorate exporters with Persistence for offline reliability.

Deliverable: works offline, flushes later, visible locally during development.

### Phase 7: Performance and Sampling
1. Provide a sampling policy strategy:
1. Always keep errors and safety blocks.
2. Dynamic downsampling under thermal/battery pressure (if you expose those signals).
2. Keep overhead predictable:
1. Avoid high-frequency span events.
2. Prefer metrics for high-volume signals (tokens, throughput, cache rates).

Deliverable: defaults safe for production.

### Phase 8: Documentation and Examples
1. Add an example under `Examples/`:
1. instrument an "agent run" with a fake model backend and fake tool calls
2. show Signpost + OTLP + Persistence configuration
2. Add docs:
1. privacy defaults
2. concurrency propagation expectations
3. how to add a backend adapter

### Definition of Done (V1)
1. A single import and `install()` call provides:
1. Instruments visibility
2. OTLP export (with offline persistence)
2. Public API is documented and Sendable-correct where needed.
3. Swift Testing suite covers:
1. span topology
2. concurrency propagation behavior
3. redaction policy behavior
4. exporter wiring smoke tests (in-memory exporters)
