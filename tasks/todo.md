# Open PR Consolidation on Main (2026-03-06)

- [x] Create isolated `main`-based integration branch/worktree for PR consolidation.
- [x] Inventory open PRs and classify them as contained, focused-value, overlapping audit, or broad/stale.
- [x] Merge or replay focused-value changes from PR #12 while dropping bookkeeping-only hunks.
- [x] Merge or replay parser hardening from PR #4 while excluding stale TraceMacApp-only changes.
- [x] Reconcile overlapping OpenTelemetry/install audit PR value into a single coherent implementation on `main`.
- [x] Selectively salvage still-applicable source/test/doc value from PR #11 without importing stale app/artifact churn.
- [x] Run targeted verification after each integration step and final `swift test` before completion.
- [x] Add review notes summarizing preserved value, skipped stale changes, and residual risks.

## Review

- Created isolated consolidation worktree at `/tmp/terra-pr-consolidation` on branch `pr-consolidation-main`, leaving the user’s existing `api-design` branch untouched.
- PR #2 (`macApp`) and PR #7 (`codex/he`) were already effectively contained on `main`; no replay was needed.
- Preserved PR #12 value in `8579dd5` by replaying the live TraceKit/OpenTelemetry hardening and dropping imported task-bookkeeping hunks.
- Preserved PR #4 value in `5fefb8b` by porting request/response parser hardening and skipping stale TraceMacApp-only changes.
- Reconciled overlapping telemetry/install audit value from PRs #3, #5, #6, #8, #9, and #10 in `8b2717d`, then followed up by preserving prior partial-install override semantics so tracer/logger overrides are not cleared by unrelated `Terra.install(.init(...))` calls.
- Selectively salvaged still-relevant TraceKit filename/discovery behavior from PR #11 in `4fdfe86` and intentionally skipped stale app/UI/artifact churn.
- Verification: `swift build` passes and full `swift test` passes on the consolidation branch.
- Residual risk is limited to intentionally skipped stale branch content that no longer matches the current repo layout or would regress current runtime behavior.

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
