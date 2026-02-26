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

## Mission-Critical Audit Remediation (2026-02-26)

- [x] Run focused code audit across core runtime, privacy, instrumentation, and trace ingestion paths.
- [x] Identify concrete correctness/safety gaps with file-level fix plans.
- [x] Add or update tests first for each identified bug path (TDD guardrails).
- [x] Implement production-grade fixes with minimal scoped changes.
- [x] Run `swift build` and full `swift test`.
- [ ] Commit with detailed message.
- [ ] Attempt push and open PR with audit + verification notes.

## Review

- Normalized OpenTelemetry install configuration before idempotency checks so non-finite sampling values (`NaN`, `±Inf`) no longer break same-config installs.
- Hardened OTLP decompression against truncated payload hangs by detecting zero-progress decode loops and requiring terminal stream status.
- Updated `TraceFileLocator` to honor numeric-prefix filenames via `TraceFileNameParser`, matching trace parser behavior.
- Removed trace file read TOCTOU risk by switching `TraceFileReader` to bounded streaming reads with live max-size enforcement.
- Tightened `OTLPHTTPServer` state access with queue-confined `start`/`stop`/`deinit`/`port` reads.
- Strengthened anonymization key fallback generation with `SystemRandomNumberGenerator` bytes instead of UUID-derived data.
- Wired `HTTPAIInstrumentation.install` default `openClawGatewayHosts` to `defaultOpenClawGatewayHosts`.
- Added regression tests for composite trace filenames, truncated deflate payloads, `.drop` redaction behavior, strict same-config concurrent install success, and non-finite sampling ratio idempotency.
- Validation:
  - `swift build` passed.
  - `swift test` passed (XCTest: 49 tests; Swift Testing: 87 tests).
