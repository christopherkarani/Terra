# Terra v1 RC Production-Readiness Completion Plan

Date: 2026-02-20  
Repository: `/Users/chriskarani/CodingProjects/Terra`  
Primary objective: finish RC hardening to true production readiness, end-to-end, with no telemetry contract drift and no UI metric blind spots.

---

## 1) Mission and Success Criteria

### Mission
Take the current RC hardening implementation from "mostly complete and passing" to "production-ready with high confidence" across:

1. Telemetry parse correctness under adversarial/unknown runtime inputs.
2. Dashboard + inspector metric plumbing parity (no silent UI drops).
3. Deterministic stress and reject-policy correctness under concurrency.
4. Portable and reproducible RC perf/CI/release gating.
5. Authoritative artifact + signoff evidence tied to current commit SHA.

### Production-ready definition (must all be true)

1. Required RC hardening gates pass via `/Users/chriskarani/CodingProjects/Terra/Scripts/rc_hardening.sh`.
2. `terra.v1` contract remains sole contract and unchanged in semantics.
3. Reject semantics remain exact:
   - Policy/runtime reject: `403` pre-ingest.
   - Schema reject: `400` pre-ingest.
4. Live-provider matrix behavior is correct in both modes:
   - Endpoints reachable: execute and assert.
   - Endpoints unavailable: explicit `XCTSkip` reasons.
5. Dashboard timeline/inspector surfaces are mutually consistent for lifecycle/hardware/recommendation/anomaly/stall signals.
6. Perf gates enforce p50 <= 3% and p95 <= 7% using stable deterministic methodology.
7. Artifacts under `/Users/chriskarani/CodingProjects/Terra/Artifacts/rc-hardening/latest` are machine-readable, current, and reproducible.
8. Root signoff document reflects current commit and latest run, not stale metadata.

---

## 2) Non-Negotiables (must not change)

1. No back-compat layer.
2. No migration tooling.
3. Keep `terra.v1` as sole contract.
4. Keep reject behavior fixed:
   - `403`: policy/runtime reject before ingest/callback.
   - `400`: schema reject before ingest/callback.
5. Null/unknown telemetry semantics must never be silently coerced to zero.
6. Live provider testing remains optional in CI if endpoints are unavailable, but failure is fatal when explicitly executed and failing.
7. Perf thresholds stay at p50 <= 0.03 and p95 <= 0.07.

---

## 3) Current Baseline Snapshot (already done)

1. RC hardening workstreams were implemented across tests, CI, script, and report.
2. `Scripts/rc_hardening.sh` exists and currently emits pass/fail JSON + text summary.
3. Live provider matrix tests exist and skip with explicit endpoint-unavailable reasons.
4. Perf suites exist for Terra core, HTTP parser, and TraceMacApp timeline prep.
5. Determinism stress tests exist for compliance suppression and OTLP mixed load.
6. Parser adversarial tests exist.
7. TraceMacApp high-volume interaction tests exist.
8. SwiftPM fixture resource warnings were cleaned up via explicit test resources.

This plan focuses on closing remaining production risks identified during deep review.

---

## 4) Open Risks to Close (from deep review)

### R1 (High): Unknown-runtime stream parser misclassification can drop lifecycle/token telemetry
Files:
- `/Users/chriskarani/CodingProjects/Terra/Sources/TerraHTTPInstrument/AIResponseStreamParser.swift`

Risk summary:
- SSE detection for unknown runtime is too permissive.
- NDJSON payloads can be misrouted into SSE parsing.
- Result: partial frame recovery and dropped chunks/lifecycle events in `.unknown` paths.

### R2 (Medium): Lifecycle event parity mismatch between timeline and inspector
Files:
- `/Users/chriskarani/CodingProjects/Terra/Sources/TraceMacApp/Timeline/TraceTimelineCanvasView.swift`
- `/Users/chriskarani/CodingProjects/Terra/Sources/TerraTraceKit/SpanDetailViewModel.swift`

Risk summary:
- Inspector lifecycle classification includes `terra.stream.lifecycle`.
- Timeline marker classification currently handles `terra.first_token` and `terra.token.lifecycle`, but can miss `terra.stream.lifecycle`.
- Result: lifecycle info visible in one surface but silently absent in another.

### R3 (Medium): Hardware event parity mismatch between timeline and inspector tabs
Files:
- `/Users/chriskarani/CodingProjects/Terra/Sources/TraceMacApp/Timeline/TraceTimelineCanvasView.swift`
- `/Users/chriskarani/CodingProjects/Terra/Sources/TerraTraceKit/SpanDetailViewModel.swift`

Risk summary:
- Timeline maps `terra.hw*`/`terra.process*` name patterns.
- Inspector hardware classification emphasizes `terra.process.*` plus attribute keys.
- Result: possible timeline marker without corresponding hardware row/tab classification.

### R4 (Medium): OTLP raw response test harness can be transport-fragile
Files:
- `/Users/chriskarani/CodingProjects/Terra/Tests/TerraTraceKitTests/OTLPHTTPServerTests.swift`

Risk summary:
- Helper may stop reading after headers and assert on incomplete bodies.
- Packet fragmentation can produce false negatives in CI.

### R5 (Medium): Perf gate default output path is not portable if env var missing
Files:
- `/Users/chriskarani/CodingProjects/Terra/Tests/TerraTests/TerraPerformanceGateTests.swift`
- `/Users/chriskarani/CodingProjects/Terra/Tests/TerraHTTPInstrumentTests/HTTPPerformanceGateTests.swift`
- `/Users/chriskarani/CodingProjects/Terra/Tests/TraceMacAppTests/TraceMacAppPerformanceGateTests.swift`

Risk summary:
- Hardcoded local-user fallback path reduces portability.

### R6 (Medium): RC signoff markdown can become stale versus actual run metadata
Files:
- `/Users/chriskarani/CodingProjects/Terra/terra-v1-rc-hardening-report.md`
- `/Users/chriskarani/CodingProjects/Terra/.github/workflows/ci.yml`
- `/Users/chriskarani/CodingProjects/Terra/Scripts/rc_hardening.sh`

Risk summary:
- Static report + uploaded artifact can diverge from actual commit/time/gate outcomes.

---

## 5) End-to-End Telemetry Plumbing Context (must remain coherent)

### Source of truth path

1. Runtime instrumentation emits spans/events/attrs via Terra keys.
2. HTTP stream parser extracts stage/lifecycle/usage/timing attributes.
3. OTLP ingest gate enforces schema/runtime policy semantics before ingest.
4. Trace store persists accepted spans.
5. View models classify events into dashboard categories/tabs/markers.
6. UI surfaces render:
   - Timeline markers.
   - Span detail tabs (events/recommendations/anomalies/lifecycle/hardware/policy).
   - Dashboard summary metrics and indicators.

### Key names currently relevant for parity

1. Lifecycle events:
   - `terra.token.lifecycle`
   - `terra.stream.lifecycle`
   - `terra.first_token`
2. Hardware names/attrs:
   - `terra.process.*`
   - `terra.hw.*`
   - Keys from `TerraTelemetryKey.hardwareAttributeKeys`.
3. Recommendation/anomaly:
   - `terra.recommendation`
   - `terra.anomaly.*`

### Parity principle

If a signal is classified and visible in one major surface (timeline, tabular inspector, dashboard summaries), it must not be silently dropped in another unless explicitly documented as intentional and tested.

---

## 6) Detailed Workstreams to Finish 100%

## WS-A: Parser Routing Hardening for Unknown Runtime (High)

Goal:
Prevent NDJSON/SSE misrouting for unknown runtime and preserve full lifecycle/token accounting.

Scope files:
- `/Users/chriskarani/CodingProjects/Terra/Sources/TerraHTTPInstrument/AIResponseStreamParser.swift`
- `/Users/chriskarani/CodingProjects/Terra/Tests/TerraHTTPInstrumentTests/AIResponseStreamParserTests.swift`
- `/Users/chriskarani/CodingProjects/Terra/Tests/TerraHTTPInstrumentTests/HTTPIntegrationTests.swift` (if needed for integration proof)

Implementation requirements:
1. Tighten SSE detection for unknown runtime.
2. Prefer robust discrimination strategy:
   - Either prove SSE framing line-level structure before selecting SSE path, or
   - Attempt NDJSON-safe parse first with clear fallback.
3. Ensure no lifecycle/token loss on mixed/adversarial payloads.
4. Preserve existing behavior for known runtimes (Ollama/LM Studio/etc.).
5. Preserve null/unknown semantics (do not default missing metrics to zero).

Test additions/updates:
1. Unknown-runtime NDJSON payload containing `data:` or `event:` substrings still parses all chunks/lifecycle events correctly.
2. Unknown-runtime true SSE payload still parses correctly.
3. Mixed malformed bursts still recover valid downstream chunks and maintain non-negative timing invariants.

Acceptance:
1. New tests fail on old behavior and pass after fix.
2. No regressions in existing parser/integration suites.

---

## WS-B: Lifecycle UI Parity (Timeline vs Inspector) (Medium)

Goal:
Ensure lifecycle telemetry appears consistently across timeline markers and inspector lifecycle tab.

Scope files:
- `/Users/chriskarani/CodingProjects/Terra/Sources/TraceMacApp/Timeline/TraceTimelineCanvasView.swift`
- `/Users/chriskarani/CodingProjects/Terra/Sources/TerraTraceKit/SpanDetailViewModel.swift`
- `/Users/chriskarani/CodingProjects/Terra/Tests/TraceMacAppTests/TraceTimelineCanvasViewTests.swift`
- `/Users/chriskarani/CodingProjects/Terra/Tests/TerraTraceKitTests/SpanDetailViewModelTests.swift` (if needed)
- `/Users/chriskarani/CodingProjects/Terra/Tests/TraceMacAppUITests/TraceAppKitViewControllerTests.swift` (if needed)

Implementation requirements:
1. Unify lifecycle classification set used by marker and inspector.
2. Explicitly include `terra.stream.lifecycle` parity.
3. Keep `terra.token.lifecycle` and `terra.first_token` handling intact.
4. Ensure marker kind/status text remains truthful under high volume.

Test additions/updates:
1. Unit test: lifecycle marker classification includes stream lifecycle names.
2. Unit/UITest: same event set appears in lifecycle tab and marker stats path.

Acceptance:
1. No lifecycle signal visible in inspector but absent in timeline classification logic.
2. Regression tests cover each supported lifecycle name.

---

## WS-C: Hardware UI Parity (Timeline vs Inspector) (Medium)

Goal:
Ensure `terra.hw.*` and `terra.process.*` hardware signals are consistently classified and rendered.

Scope files:
- `/Users/chriskarani/CodingProjects/Terra/Sources/TraceMacApp/Timeline/TraceTimelineCanvasView.swift`
- `/Users/chriskarani/CodingProjects/Terra/Sources/TerraTraceKit/SpanDetailViewModel.swift`
- `/Users/chriskarani/CodingProjects/Terra/Sources/TraceMacApp/ViewModels/DashboardViewModel.swift` (consistency check)
- `/Users/chriskarani/CodingProjects/Terra/Tests/TraceMacAppTests/TraceTimelineCanvasViewTests.swift`
- `/Users/chriskarani/CodingProjects/Terra/Tests/TerraTraceKitTests/SpanDetailViewModelTests.swift` (if needed)

Implementation requirements:
1. Harmonize name-prefix and attribute-key based hardware classification across timeline and inspector.
2. Ensure hardware tabs include same event universe as marker classification.
3. Preserve existing recommendation/anomaly/policy grouping.

Test additions/updates:
1. `terra.hw.*` event-name case.
2. `terra.process.*` event-name case.
3. Attribute-only hardware event case.

Acceptance:
1. Any hardware marker has matching inspector categorization, and vice versa.

---

## WS-D: OTLP Test Harness Robustness (Medium)

Goal:
Remove transport-level flakiness in OTLP reject stress tests.

Scope files:
- `/Users/chriskarani/CodingProjects/Terra/Tests/TerraTraceKitTests/OTLPHTTPServerTests.swift`

Implementation requirements:
1. Make raw HTTP response reader consume complete body (e.g., via `Content-Length` or until close) before assertions.
2. Keep concurrency stress semantics and expected status counts unchanged.
3. Keep `403`/`400` policy/schema assertions exact.

Test requirements:
1. Existing mixed concurrent stress test remains deterministic across repeated runs.
2. No false negatives from partial body reads.

Acceptance:
1. Stress tests pass repeatedly with stable outcomes.

---

## WS-E: Perf Gate Portability + Stability (Medium)

Goal:
Maintain strict thresholds while ensuring gates are portable and stable.

Scope files:
- `/Users/chriskarani/CodingProjects/Terra/Tests/TerraTests/TerraPerformanceGateTests.swift`
- `/Users/chriskarani/CodingProjects/Terra/Tests/TerraHTTPInstrumentTests/HTTPPerformanceGateTests.swift`
- `/Users/chriskarani/CodingProjects/Terra/Tests/TraceMacAppTests/TraceMacAppPerformanceGateTests.swift`

Implementation requirements:
1. Keep threshold semantics exactly:
   - pass iff p50 <= 0.03 and p95 <= 0.07.
2. Keep overhead formula semantically correct:
   - `(instrumented - baseline) / baseline`.
3. Ensure measurement design is deterministic enough for RC gating:
   - warmup,
   - fixed samples,
   - stable percentile calculation,
   - controlled per-sample repetitions if needed.
4. Replace machine-specific fallback output path with portable repo-based fallback if env var missing.
5. Preserve output artifact filenames for CI consumers.

Acceptance:
1. Gates pass in intended RC environment with deterministic behavior.
2. No reliance on a user-specific filesystem path.

---

## WS-F: RC Automation and Signoff Artifact Freshness (Medium)

Goal:
Ensure CI artifacts represent current run truth.

Scope files:
- `/Users/chriskarani/CodingProjects/Terra/Scripts/rc_hardening.sh`
- `/Users/chriskarani/CodingProjects/Terra/.github/workflows/ci.yml`
- `/Users/chriskarani/CodingProjects/Terra/terra-v1-rc-hardening-report.md`

Implementation requirements:
1. Ensure report includes current SHA/timestamps and gate status from latest run.
2. Ensure CI uploads authoritative machine-readable summary and supporting artifacts.
3. Keep PR pipeline lightweight; RC-heavy path only for RC contexts.
4. Keep live provider step optional + explicit on skips.

Acceptance:
1. Uploaded report and summary match current run metadata.
2. No stale SHA/date in signoff evidence.

---

## 7) Command Matrix for Final Validation

Run from `/Users/chriskarani/CodingProjects/Terra`:

1. `TERRA_ENABLE_PERF_GATES=1 swift test --filter TerraPerformanceGateTests`
2. `TERRA_ENABLE_PERF_GATES=1 swift test --filter HTTPPerformanceGateTests`
3. `TERRA_ENABLE_PERF_GATES=1 swift test --filter TraceMacAppPerformanceGateTests`
4. `swift test --filter TerraCompliancePolicyTests.testConcurrentPolicySuppression_isDeterministicAcrossRepeatedRounds`
5. `swift test --filter OTLPHTTPServerTests.testOTLPHTTPServerMixedConcurrentAllowRejectStressIsDeterministic`
6. `swift test --filter 'AIResponseStreamParserTests|HTTPIntegrationTests'`
7. `swift test --filter TerraV1FixtureTests`
8. `TERRA_ENABLE_LIVE_PROVIDER_TESTS=1 swift test --filter LiveProviderIntegrationTests`
9. `./Scripts/rc_hardening.sh`

Additional hygiene check:
1. Validate no TerraV1 fixture "unhandled files" warnings in test output.

Expected run semantics:
1. Live tests:
   - Pass when endpoints available.
   - Skip with explicit reason when unavailable.
2. RC script:
   - Overall pass only if all required gates pass.
   - Machine-readable summary and text summary produced.

---

## 8) Required Final Deliverables

Artifacts under:
- `/Users/chriskarani/CodingProjects/Terra/Artifacts/rc-hardening/latest/`

Required files:
1. `rc-hardening-summary.json`
2. `rc-hardening-summary.txt`
3. `terra-performance-gate.json`
4. `terra-performance-gate.txt`
5. `http-performance-gate.json`
6. `http-performance-gate.txt`
7. `tracemacapp-performance-gate.json`
8. `tracemacapp-performance-gate.txt`
9. Step logs from RC script.

Root signoff:
1. `/Users/chriskarani/CodingProjects/Terra/terra-v1-rc-hardening-report.md`
2. Must contain:
   - current commit SHA,
   - exact commands used,
   - pass/skip/fail status,
   - residual risks,
   - deferred items (if any),
   - explicit Go/No-Go decision.

---

## 9) Execution Order (strict)

1. Fix parser routing (WS-A), then parser/integration tests.
2. Fix lifecycle parity (WS-B), then UI classification tests.
3. Fix hardware parity (WS-C), then UI classification tests.
4. Harden OTLP test harness (WS-D), then stress reruns.
5. Finalize perf gate portability/stability (WS-E), then perf reruns.
6. Finalize CI/report freshness (WS-F).
7. Run full validation matrix.
8. Regenerate artifacts + finalize signoff doc.

---

## 10) Agent Guardrails (implementation discipline)

1. Do not weaken tests to hide defects.
2. Do not relax threshold constants.
3. Do not change public telemetry contract semantics.
4. Do not change reject status code behavior.
5. Keep changes minimal, explicit, and covered by regression tests.
6. Favor shared classification helpers if parity logic is duplicated.
7. Record any intentional behavior change in test names and report notes.

---

## 11) Completion Checklist

### Parser and invariants
- [ ] Unknown-runtime NDJSON with `data:`/`event:` text does not misroute and lose lifecycle chunks.
- [ ] Unknown-runtime true SSE still parses correctly.
- [ ] Adversarial timestamp/malformed-frame invariants still pass.

### UI plumbing parity
- [ ] `terra.stream.lifecycle` classification parity exists between timeline and inspector.
- [ ] Hardware classification parity exists for `terra.hw.*` and `terra.process.*`.
- [ ] High-volume timeline/inspector interaction tests still pass.

### Stress/reject determinism
- [ ] Compliance suppression stress deterministic across repeated rounds.
- [ ] OTLP mixed allow/reject/schema stress deterministic and robust to transport fragmentation.
- [ ] `403` policy/runtime and `400` schema semantics verified pre-ingest.

### Perf gates
- [ ] p50/p95 thresholds enforced exactly.
- [ ] Perf gate artifact output path portable if env var missing.
- [ ] JSON/text artifacts deterministic and present.

### CI/Release
- [ ] RC workflow paths and script invocation are correct.
- [ ] Report and summary metadata are current and authoritative.
- [ ] RC summary artifact indicates pass on required gates.

### Final signoff
- [ ] `/Users/chriskarani/CodingProjects/Terra/terra-v1-rc-hardening-report.md` updated with current SHA and Go/No-Go.
- [ ] Residual risks explicitly documented.
- [ ] Deferred items explicitly documented (or "None").

---

## 12) Final Output Requirements for Coding Agent

At the end of execution, provide:

1. Findings fixed (with path + line references).
2. Full file change list.
3. Command execution summary with pass/skip/fail.
4. Perf p50/p95 per workload from generated artifacts.
5. Final verdict: `GO` or `NO-GO`.
6. If `NO-GO`, exact blockers and shortest critical path to `GO`.

