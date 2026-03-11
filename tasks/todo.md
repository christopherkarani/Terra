# TraceMacApp Extraction Verification

- [x] Baseline current repo state and identify remaining TraceMacApp coupling.
- [x] Remove in-repo TraceMacApp leftovers that conflict with extraction.
- [x] Update docs/scripts to point to TerraViewer ownership.
- [x] Run `swift build`.
- [x] Run full `swift test`.
- [x] Add review notes and residual risks.

## Review

- `Package.swift` has no TraceMacApp targets/products and CI remains SwiftPM-focused.
- Removed stale TraceMacApp release scripts under `Scripts/release/` that referenced `Apps/TraceMacApp`.
- Updated README to reference TerraViewer as the standalone Trace viewer owner.
- Removed stale local `Apps/TraceMacApp` workspace directory.
- Fixed SwiftPM manifest hygiene: removed invalid missing test resource (`Fixtures/TerraV1`) and excluded in-target `CLAUDE.md` files to eliminate local package warnings.
- `swift build` succeeds.
- `swift test` succeeds after stabilizing `OTLPHTTPServerTests` to wait for ephemeral port binding before issuing requests.
- Residual warning scope: only third-party dependency/plugin deprecation warnings remain (outside Terra-owned source).

## TerraCore Privacy Audit

- [x] Draft audit plan and checkpoints (this entry is the plan record).
- [x] Review Terra privacy-related sources for data leakage, redaction, crypto, logging, retention, and export control risks.
- [x] Summarize prioritized findings with file/line references, fixes, and tests.

## Concurrency Audit (New Work)

- [x] Draft plan for scanning Terra concurrency primitives / shared singletons.
- [x] Review `Sources/Terra` files for `Sendable` markers, locks, actors, `Task.detached`, context propagation.
- [x] Enumerate findings / correctness notes with prioritization and suggest regression tests.

## TraceKit Ingestion/Security Audit

- [x] Confirm scope and assumptions (files, threat categories, testability) before deep dive.
- [x] Review listed TerraTraceKit sources for DoS, parsing, concurrency, and filesystem risks.
- [x] Summarize prioritized findings and mitigation suggestions, noting verification follow-ups.

## Build/CI/Deps Audit

- [x] Record audit scope, files, and success criteria (this entry is the plan checkpoint).
- [x] Review `Package.swift`, `Package.resolved`, and `.github/workflows/ci.yml` for dependency pinning, supply-chain, and CI gaps.
- [x] Audit `Scripts/` and `Docs/` for release automation risks, lint/config coverage, and missing documentation.
- [x] Summarize prioritized findings, quick wins, and verification steps for handoff.

## Audit Review (2026-02-24)

- Full report: `tasks/audit.md`
- `swift test` is green; stabilized HTTP integration test to avoid relying on a MockURLProtocol + `URLSession.data(for:)` path that wasn’t reliably producing finished spans in this environment.

## URLSessionInstrumentation investigation

- [x] Confirm how TerraHTTPInstrument configures instrumentation and where `url.full` is emitted (`Sources/TerraHTTPInstrument/HTTPAIInstrumentation.swift`).
- [x] Research dependency enums/options that let us keep request/response callbacks without emitting `url.full` and catalog their names/locations.
- [x] Recommend the best implementation path (code changes or configuration) and document the patch guidance.

## TerraTraceKit Decoder Tests

- [x] Survey TerraTraceKit server/decoder tests and helpers for current coverage of timeouts, limit enforcement, and span encoding.
- [x] Identify reusable fixtures/helpers for crafting headers, bodies, spans, attribute sets, and nested AnyValue data.
- [x] Draft concrete test case proposals (with helper pattern suggestions) for header/body read timeout, cancel on connection close, max spans per request, max attributes per span, and AnyValue nesting depth; note fixtures to reuse.

## Audit Remediation Review (2026-02-25)

- `HTTPAIInstrumentation` now uses URLSession semantic convention `.old`, preserving request/response callbacks while avoiding `url.full`.
- Added explicit verification in `HTTPIntegrationTests` that `url.full` is not emitted.
- Added OTLP decoder budgets (`maxSpansPerRequest`, `maxAttributesPerSpan`, `maxAnyValueDepth`) plus regression tests.
- Added OTLP HTTP server header/body read timeouts, `408 Request Timeout` handling, and timeout-focused tests.
- Added trace file max-size guard in `TraceFileReader` with oversize failure test coverage.
- Strengthened privacy defaults by making legacy SHA attributes opt-in (`emitLegacySHA256Attributes: false`), with updated redaction tests and README notes.
- Validation: `swift test --filter TerraRedactionPolicyTests` and full `swift test` both pass.

## Mission-Critical Framework Audit (2026-03-11)

- [x] Read prior automation memory + current audit artifacts to avoid duplicate work.
- [x] Run baseline `swift build` and `swift test` to detect current regressions.
- [x] Perform static audit for correctness/safety issues (concurrency, parsing, lifecycle, dead paths).
- [x] Prioritize findings (P0-P2), implement production-grade fixes with minimal impact.
- [x] Add/adjust regression tests first (TDD-style) for each confirmed issue.
- [x] Re-run targeted tests, then full `swift test` and `swift build`.
- [ ] Prepare commit(s) with detailed messages and open PR.
- [x] Add review summary and residual risks under this section.

### Review

- Fixed a request-lifecycle correctness bug in `OTLPHTTPServer`: once a response path begins (especially timeout/error), later queued reads/decode cannot ingest spans for that connection.
- Added resource-attribute budget enforcement in `OTLPRequestDecoder.Limits` (`maxResourceAttributes`) to prevent unbounded resource metadata fan-out across spans.
- Fixed sticky runtime install state in `Runtime.install(_:)` by clearing tracer/logger overrides when omitted and resetting metrics instruments when `meterProvider` is nil.
- Removed shared mutable stream token-probe state from `TerraTracedSession` and scoped it per stream to avoid cross-stream races.
- Added regression coverage:
  - `OTLPHTTPServerTests.testOTLPHTTPServer_timeoutIgnoresLateBodyData`
  - `OTLPRequestDecoderTests.testDecodeRejectsWhenResourceAttributesExceedLimit`
  - `TerraRuntimeInstallTests.testInstallClearsTracerProviderOverrideWhenUnset`
- Verification:
  - `swift test --filter OTLPHTTPServerTests --filter OTLPRequestDecoderTests`
  - `swift test --filter TerraRuntimeInstallTests`
  - `swift test --no-parallel` (full pass; avoids known global-state flake in parallel Swift Testing mode)
  - `swift build`
- Residual risk: `installOpenTelemetry` partial-install rollback and HTTP instrumentation reconfiguration semantics remain as follow-up work outside this patch set.

## Terra Source Review Audit (2026-03-11)

- [x] Record review-only scope for `Sources/Terra`, `Sources/TerraHTTPInstrument`, and `Sources/TerraFoundationModels`.
- [x] Inspect target sources plus adjacent tests/usages for correctness, concurrency, and lifecycle failures.
- [x] Rank the top 3-5 concrete findings with break scenarios and patch suggestions.
- [x] Add review summary and residual risk notes under this section.

### Review

- Top findings: sticky `Runtime.install` state leaks provider/key configuration across installs; `installOpenTelemetry` can leave a half-installed global stack on failure; `TerraTracedSession` shares an unsynchronized token-count probe flag across streams; `HTTPAIInstrumentation.resetForTesting()` only drops the wrapper reference, so repeated install/reset cycles do not cleanly tear down instrumentation; `HTTPAIInstrumentation.install()` silently ignores later host/mode changes.
- Adjacent tests cover happy paths for tracing/context propagation and basic HTTP instrumentation, but they do not currently exercise reconfiguration, rollback, or repeated install/reset behavior.
- Full verification now succeeds with `swift test --no-parallel` and `swift build`.
