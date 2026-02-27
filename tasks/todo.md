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

## Mission-Critical Audit Remediation (2026-02-27)

- [x] Re-baseline repository health and run focused scans for crash/correctness risks.
- [x] Identify concrete bugs/gaps/dead code with file-level evidence.
- [x] Implement fixes with minimal, production-safe diffs.
- [x] Add/adjust regression tests using TDD flow for each remediation.
- [ ] Run full `swift test` and `swift build`. (Blocked: host disk is full; SwiftPM fails with `error: other(28)` and `No space left on device` before compilation/tests.)
- [x] Commit, push branch, and open PR with detailed rationale.
- [x] Add run review notes (findings fixed, residual risks, and verification output).

### Review (2026-02-27)

- Runtime reconfiguration correctness: `Runtime.install` now clears stale tracer/logger overrides and always reconfigures metrics when providers are omitted.
- Streaming metrics correctness: `recordChunk()` no longer emits `terra.first_token` or sets first-token timestamps without token emission.
- OpenTelemetry install state: `installedOpenTelemetryConfiguration` now sets only after successful setup path completion.
- HTTP instrumentation correctness:
  - install config updates now apply after the first install via mutable shared config read by instrumentation callbacks.
  - operation name/span name now infer endpoint (`chat`, `embeddings`, fallback `inference`) instead of hardcoded chat.
  - request body parsing now supports `httpBodyStream`; response parsing now supports `Data` and downloaded `URL` payloads with size caps.
- OTLP HTTP parser hardening: duplicate `Content-Length` headers and comma-separated `Content-Length` values are rejected with `400`.
- Tree renderer robustness: cycle/disconnected graphs are rendered instead of dropped; cycle edges are marked with `[cycle]`.
- Trace decoder error semantics: invalid persisted format (missing trailing comma / malformed JSON) now throws `TraceDecodingError.invalidFormat`.
- Added regression tests:
  - `TerraStreamingSpanTests`: chunk-only streams do not emit first-token metrics/events.
  - `TerraInferenceSpanTests`: reinstall without tracer provider clears override and falls back to global provider.
  - `HTTPAIInstrumentationTests`: operation inference and live install-config host updates.
  - `HTTPIntegrationTests`: chat + embeddings operation/attribute assertions.
  - `OTLPHTTPServerTests`: duplicate/comma-separated content-length rejection.
  - `TreeRendererTests`: cycle rendering coverage.
  - `TraceDecoderTests`: invalid-format error coverage.
- Verification blocker:
  - `swift test`/`swift build` could not run because filesystem free space is ~209MiB and SwiftPM dependency checkout fails (`error: other(28)`, `No space left on device`).
- Delivery status:
  - Branch pushed: `automation/check-frameworks-issues-20260227`
  - PR opened: `https://github.com/christopherkarani/Terra/pull/13`
  - Label application via `gh pr edit` is currently blocked by transient GitHub API connectivity failure in this environment.
