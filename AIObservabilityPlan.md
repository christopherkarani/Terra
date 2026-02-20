# Terra Observability Plan (HEAD-Aligned)

Date: 2026-02-20

This plan replaces the earlier bootstrap roadmap and reflects what is already implemented in `main`.

## Why Rewrite

The previous plan treated foundational work as future tasks (package setup, core span APIs, OTel install flow, streaming scope, resource attributes, and multiple backend modules). Those are already shipped. This version focuses only on unresolved gaps and measurable next moves.

## Current Baseline (Already Implemented)

1. Core span APIs and scope helpers are in place:
1. `withInferenceSpan`
2. `withStreamingInferenceSpan`
3. `withAgentInvocationSpan`
4. `withToolExecutionSpan`
5. `withEmbeddingSpan`
6. `withSafetyCheckSpan`
2. Streaming telemetry is implemented:
1. first-token event
2. chunk count
3. output token count
4. TTFT
5. tokens/sec
3. Privacy model is implemented:
1. content policy (`never` / `optIn` / `always`)
2. redaction strategy (`drop` / `lengthOnly` / `hashSHA256`)
4. OpenTelemetry install flow is implemented:
1. Signpost and OTLP paths
2. persistence integration
3. `service.name` and `service.version` resource attributes
5. Auto-instrumentation exists for:
1. Core ML
2. HTTP AI providers
3. OpenClaw diagnostics export path
6. Optional profilers are already shipped:
1. `TerraMetalProfiler`
2. `TerraSystemProfiler` (memory deltas)
7. Existing tests already cover:
1. span types
2. streaming span behavior
3. E2E span export/load flow
4. host boundary matching
5. TraceKit concurrent access

## Confirmed Gaps To Prioritize

### G1 (High): Response parser has no size guard before JSON parse

- `Sources/TerraHTTPInstrument/AIResponseParser.swift` parses arbitrary payload size with `JSONSerialization`.
- `AIRequestParser` has a 10 MiB guard; response path should match.
- Risk: large response payload can trigger avoidable allocation pressure.

### G2 (Medium): CoreML dedup guard is intentionally non-atomic

- `Sources/TerraCoreML/CoreMLInstrumentation.swift` uses `activeSpan == nil` check without synchronization.
- In highly concurrent predictions this can emit duplicate auto-instrumented spans.
- Current comment documents this tradeoff; decision needed whether to keep or harden.

### G3 (High): Foundation Models non-stream token usage is incomplete

- `Sources/TerraFoundationModels/TerraTracedSession.swift` streaming path records chunk/tokens when surfaced, but non-stream `respond` paths do not set usage attributes.
- Add explicit token usage capture for supported OS/SDK levels and map to `gen_ai.usage.*`.

### G4 (Medium): Foundation Models test depth is minimal

- Current tests only validate initialization/stub compile behavior.
- Missing behavior tests for span attributes/events under available Foundation Models environments.

### G5 (Medium): No direct llama.cpp runtime bridge yet

- `TerraLlama` currently provides instrumentation wrappers/hooks, but no bundled C/C++ bridge into llama.cpp decode callbacks.
- This is a product expansion item, not a blocker for current Terra core quality.

## Execution Plan (Net-New Work Only)

### Phase A: Production Hardening (1 sprint)

1. Implement response body size guard in `AIResponseParser`.
2. Add parser test for oversized responses mirroring request parser behavior.
3. Decide CoreML dedup strategy:
1. Keep current lock-free approach and formally classify as known behavior with explicit docs and test.
2. Or add synchronized dedup path (feature-flagged or default) if duplicate telemetry is unacceptable.
4. Add concurrency-focused test(s) for CoreML dedup behavior at the selected policy.

Acceptance:
1. Oversized response payload returns `nil` without deserialization.
2. Dedup behavior is deterministic and documented (either guaranteed or explicitly best-effort).

### Phase B: Foundation Models Telemetry Completion (1 sprint)

1. Add token usage attributes for non-stream `respond` flows.
2. Improve streaming token accounting fallback where explicit token counters are absent.
3. Add context-window attribute when available.
4. Guard all API usage with precise availability checks.

Acceptance:
1. On supported SDKs, `respond` spans include input/output usage attributes.
2. Streaming spans still emit TTFT/tokens/sec and remain backward compatible.
3. Module continues compiling cleanly on platforms without Foundation Models.

### Phase C: Test and Verification Hardening (partial sprint)

1. Expand Foundation Models behavior tests (availability-gated).
2. Add/adjust CI tests for Phase A/B behaviors using in-memory exporters.
3. Split verification into:
1. CI-required checks (deterministic, no external tooling dependency).
2. manual macOS checks (Instruments/Signpost visibility and end-to-end OTLP environment checks).

Acceptance:
1. CI does not depend on Instruments UI or live collector availability.
2. Manual checklist exists for Signpost and OTLP validation on macOS.

### Phase D: Ecosystem Expansion (separate track)

1. Design `TerraLlama` native bridge surface (C module + Swift wrapper).
2. Implement per-token callback ingestion and span-event batching.
3. Add focused tests around callback ordering and throughput overhead.

Acceptance:
1. llama.cpp-based generation can emit token timing and throughput metrics through Terra spans.
2. Bridge overhead and failure modes are documented.

## Verification Matrix

### CI Required

1. `swift build`
2. `swift test`
3. Targeted tests for:
1. response size guard
2. CoreML dedup policy behavior
3. Foundation Models token usage behavior (availability-gated)

### Manual (macOS)

1. Verify Signpost visibility in Instruments for representative inference spans.
2. Verify OTLP + persistence flow in a local collector/dev backend environment.
3. Verify TraceMacApp rendering for newly added attributes.

## Files Expected To Change

### Phase A

1. `Sources/TerraHTTPInstrument/AIResponseParser.swift`
2. `Tests/TerraHTTPInstrumentTests/AIRequestParserTests.swift`
3. `Sources/TerraCoreML/CoreMLInstrumentation.swift` (if dedup policy changes)
4. `Tests/TerraCoreMLTests/TerraCoreMLTests.swift` (plus/or new concurrency-focused test file)

### Phase B

1. `Sources/TerraFoundationModels/TerraTracedSession.swift`
2. `Tests/TerraFoundationModelsTests/TerraTracedSessionTests.swift`
3. `Sources/Terra/Terra+Constants.swift` (if new keys are required)

### Phase C

1. Test files under `Tests/TerraTests`, `Tests/TerraFoundationModelsTests`, and `Tests/TerraHTTPInstrumentTests`
2. Optional doc/checklist updates in `Docs/` or `README.md`

### Phase D

1. `Sources/TerraLlama/`
2. `Sources/TerraLlama/include/`
3. `Package.swift`
4. `Tests/TerraLlamaTests/`

## Explicitly Out of Scope For This Plan Revision

1. Re-implementing already shipped core APIs.
2. Reworking already implemented resource attributes or diagnostics-mode plumbing.
3. Forcing CI to run full external OTLP or Instruments UI workflows.
