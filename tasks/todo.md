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

## Swift 6.2 Public API Concurrency & Evolution Audit (2026-02-26)

- [x] Inventory public API entry points across `Terra*` products and identify global/shared state patterns.
- [x] Run `swift build -Xswiftc -strict-concurrency=complete` and capture concurrency diagnostics relevant to Terra-owned code.
- [x] Audit install/start semantics for idempotency, stickiness, and ability to shut down/reconfigure.
- [x] Review `@unchecked Sendable`, `NSLock`, and actor suitability in public-facing types.
- [x] Produce concrete API evolution proposal with progressive-disclosure layers (basic -> advanced).

## Review

- Verified strict-concurrency warnings in Terra-owned code:
  - `Sources/Terra/Terra+OpenTelemetry.swift` static mutable install state warning.
  - `Sources/Terra/Terra+Runtime.swift` singleton/global state warnings.
  - `Sources/Terra/Terra+Convenience.swift` non-Sendable `AttributeValue` captured in `@Sendable` closures.
- Confirmed sticky install behavior (`alreadyInstalled` semantics) from tests in `Tests/TerraTests/TerraOpenTelemetryInstallConcurrencyTests.swift`.
- Confirmed no public lifecycle API for `shutdown/reconfigure` despite global provider registration and multiple sticky one-way `install()` calls.
- Logged concrete redesign proposal (handle-based runtime, actor-backed state, explicit lifecycle, typed events, and configurable sampling/batching/storage/export).

## Front-Facing API Ergonomics Upgrade (2026-02-26)

- [x] Add additive onboarding API that defaults to quick-start while preserving existing `Terra.start(...)` behavior.
- [x] Add typed telemetry helper APIs so common attributes do not require raw string keys.
- [x] Fix the streaming convenience function signature mismatch in `Sources/Terra/Terra+Convenience.swift`.
- [x] Follow TDD flow: add/adjust tests first for new APIs, then implement.
- [x] Update README/examples/docs to highlight the new recommended entry points.
- [x] Run focused test suites and `swift build`.
- [x] Add review notes with outcomes, compatibility, and residual risks.

## Review

- Added new onboarding façade `Terra.bootstrap(_:)` (default `.quickstart`) plus `Terra.start(_ preset:configure:)` for cleaner preset-driven startup.
- Preserved backwards compatibility: existing `Terra.start(preset:configure:)` and `Terra.start(_ config:)` remain supported.
- Added typed helper methods for expert telemetry:
  - `scope.setRuntime(_:)`
  - `scope.setProvider(_:)`
  - `scope.setResponseModel(_:)`
  - `scope.setTokenUsage(input:output:)`
  - `stream.recordChunk(tokens:)`
- Fixed compile-time mismatch in `withStreamingInferenceSpan(model:...)` to accept `StreamingInferenceScope`.
- Updated README, integrations docs, auto-instrument example, website code snippet, and changelog to align with the new API surface.
- Verification:
  - Targeted red/green loop: `TerraStartTests`, `TerraInferenceSpanTests`, `TerraStreamingSpanTests`.
  - Full validation: `swift build` and full `swift test` passed (0 failures).
- Residual risk: existing non-blocking deprecation warning remains in `Sources/TerraTraceKit/OTLPDecoder.swift` (`serializedData` initializer), outside this API ergonomics scope.

## Terra V2 Fluent Call-Site Overhaul (2026-02-27)

- [x] Add fluent operation builders with `.run { ... }` across inference/stream/embedding/agent/tool/safety-check.
- [x] Add actor-based `Terra.Session` call-surface with matching operation builders.
- [x] Add typed custom telemetry extension points: `AttributeKey`, `AttributeBag`, `TelemetryValue`, `TerraEvent`.
- [x] Migrate wrappers (`TerraMLX`, `TerraLlama`, `TerraFoundationModels`) to fluent call-sites.
- [x] Update `@Traced` macro expansion to `Terra.inference(...).run`.
- [x] Add new fluent API tests and keep existing behavior tests green.
- [x] Update docs/examples/website snippets and add migration/spec docs.

## Review

- Implemented fluent v2 call objects: `InferenceCall`, `StreamingCall`, `EmbeddingCall`, `AgentCall`, `ToolCall`, `SafetyCheckCall`.
- Added top-level fluent builders and shared session API:
  - `Terra.inference(...)`, `Terra.stream(...)`, `Terra.embedding(...)`, `Terra.agent(...)`, `Terra.tool(...)`, `Terra.safetyCheck(...)`
  - `Terra.shared()`
- Added `Terra.Session` actor with matching operation methods for DI-friendly usage.
- Added trace context types for dynamic telemetry:
  - `InferenceTrace`, `StreamingTrace`, `EmbeddingTrace`, `AgentTrace`, `ToolTrace`, `SafetyCheckTrace`
- Converted legacy `with*Span` entrypoints to internal-only APIs (no longer public-facing).
- Removed the accidental public convenience overload layer (`Terra+Convenience.swift`) so v2 only exposes fluent `.run` call-sites.
- Added request models for expert flow:
  - `InferenceRequest`, `StreamingRequest`, `EmbeddingRequest`, `AgentRequest`, `ToolRequest`, `SafetyCheckRequest`
  - plus fluent request modifiers (`maxOutputTokens`, `temperature`, `expectedOutputTokens`).
- Added docs:
  - `Docs/API_V2_FLUENT_CALLSITE_SPEC.md`
  - `Docs/Migration_v1_to_v2.md`
- Validation:
  - `swift build` ✅
  - `swift test` ✅ (all tests passing)

## Terra API V3 Implementation (2026-03-01)

- [x] Add migration guardrail dependency: `swift-testing` product to `TerraTests` target.
- [x] Add v3 privacy/config foundations:
  - `Terra.PrivacyPolicy` (`Sources/Terra/Terra+PrivacyV3.swift`)
  - `Terra.V3Configuration` (`Sources/TerraAutoInstrument/Terra+Start.swift`)
  - `Terra.Key` typed constants (`Sources/Terra/Terra+KeyV3.swift`)
- [x] Extract trace protocol/types into dedicated source:
  - `Sources/Terra/Terra+TraceProtocol.swift`
  - remove duplicate trace declarations from `Terra+FluentAPI.swift`
- [x] Add closure-first API overloads and builder terminal migration:
  - `.execute {}` terminals on all call types
  - keep deprecated `.run {}` forwarders
  - add `.includeContent()` and keep deprecated `.capture(...)` wrappers
- [x] Add `TerraTraceable` + automatic result extraction for inference spans:
  - `Sources/Terra/TerraTraceable.swift`
  - extraction wiring in `Session.runInference`
- [x] Add task-local `AgentContext` and aggregate agent metadata:
  - `Sources/Terra/Terra+AgentContext.swift`
  - context wiring in `runAgent` / `runTool` / `runInference`
- [x] Expand traced macro coverage:
  - new declarations in `Sources/TerraTracedMacro/Traced.swift`
  - new expansion logic in `Sources/TerraTracedMacroPlugin/TracedMacro.swift`
  - rewritten macro expansion tests
- [x] Migrate wrappers/examples/docs to v3 surface:
  - wrappers use `.execute`
  - examples use `Terra.start()`
  - README updated with 3-line v3 hello-world
- [x] Add v3 test files:
  - `Tests/TerraTests/TerraPrivacyV3Tests.swift`
  - `Tests/TerraAutoInstrumentTests/TerraConfigurationV3Tests.swift`
  - `Tests/TerraTests/TerraTraceProtocolTests.swift`
  - `Tests/TerraTests/TerraClosureAPITests.swift`
  - `Tests/TerraTests/TerraKeyV3Tests.swift`
  - `Tests/TerraTests/TerraTraceableTests.swift`
  - `Tests/TerraTests/TerraAgentContextTests.swift`
- [x] Stabilize parallel Swift Testing global runtime races:
  - add DEBUG testing isolation lock in `Terra+OpenTelemetry.swift`
  - apply lock usage in `TerraTestSupport` and `TerraMLXTests` harness
- [x] Verify migration:
  - `swift test` passes (XCTest: 51/0 failures, Swift Testing: 107 passed)

## Review

- API v3 additive migration is in place with compatibility shims (`.run`, `.capture`, `enable/configure` deprecations).
- Fluent call-sites and macros now target `.execute`.
- New v3 tests are present and compile; full suite is green.
- Residual compatibility docs (`Docs/API_V2_FLUENT_CALLSITE_SPEC.md`, `Docs/Migration_v1_to_v2.md`) intentionally remain to document prior v2 surface during migration window.

## Terra API 100% Readiness Plan (Proposed)

- [ ] **Phase 1: Canonical Public Surface Freeze**
- [ ] Declare one startup entrypoint as canonical (recommended: `Terra.start(...)` + single preset/config style).
- [ ] Finalize naming policy (remove versioned naming from public API where possible, e.g. `V3Configuration` -> stable `Configuration`).
- [ ] Define public API stability contract and deprecation window (dates + versions).
- [ ] Exit criteria: public API map approved, no ambiguous "preferred" paths in docs.

- [x] **Phase 2: Configuration Consolidation**
- [x] Collapse overlapping config models (`AutoInstrumentConfiguration`, `V3Configuration`, legacy wrappers) into one primary model plus compatibility adapters.
- [x] Ensure diagnostics/production/quickstart presets are behaviorally distinct and documented.
- [x] Add config round-trip/unit tests for all presets and key overrides.
- [x] Exit criteria: one canonical config type for new users; old types deprecated with compile-time guidance.

## Phase 2 Review (2026-03-01)

- `Terra.Configuration` is now the single canonical config type with fields: `profiling`, `openClaw`, `excludedCoreMLModels`, `enableLogs`.
- `AutoInstrumentConfiguration` and `StartProfile` are deprecated with compile-time guidance messages.
- `asAutoInstrumentConfiguration()` is now public and correctly wires all new fields through.
- Preset parity gaps fixed: `.diagnostics` preset now enables profilers, logs, and openClaw diagnostics mode.
- `StartProfile.quickstart` aligned: `enableSessions: true` (was `false`), matching `Configuration` default.
- `StartProfile` presets aligned to match `Configuration` conversion output for privacy (`contentPolicy: .optIn`), metrics interval, and resource attributes.
- 25 new/updated tests in `TerraConfigurationV3Tests.swift` covering defaults, preset fields, round-trip conversion, and preset equivalence.
- All competing `start()` overloads deprecated; `Terra.start(_: Configuration = .init())` is the canonical entry point.
- README, example `main.swift`, and docs updated to show canonical API.
- Verification: `swift test --filter TerraAutoInstrumentTests` passes 42 tests.

- [x] **Phase 3: Runtime Lifecycle Hardening**
- [x] Add explicit lifecycle APIs for advanced users (`shutdown/reconfigure` or handle-based runtime) while preserving simple global defaults.
- [x] Guarantee deterministic behavior for repeated install/start in app + tests.
- [x] Add concurrency stress tests for runtime state transitions.
- [x] Exit criteria: lifecycle semantics documented and validated under parallel tests.

## Phase 3 Review (2026-03-02)

- Added `Terra.LifecycleState` enum (`.uninitialized` / `.running`) with `Sendable` + `Equatable` conformance.
- Added public APIs: `Terra.lifecycleState`, `Terra.isRunning`, `Terra.shutdown() async`.
- `shutdown()` performs full provider flush and teardown:
  - `TracerProviderSdk`: `forceFlush()` + conditional `shutdown()` (only when Terra owns the provider).
  - `MeterProviderSdk`: `forceFlush()` + `shutdown()`.
  - `LogRecordProcessor`: `forceFlush()` + `shutdown()`.
  - Lock released before I/O — refs atomically claimed under the install lock.
- Provider ownership tracking: `.augmentExisting` strategy marks provider as borrowed; `shutdown()` flushes but does not tear down borrowed providers.
- `resetOpenTelemetryForTesting()` also resets lifecycle state and clears all provider refs.
- 8 deterministic lifecycle tests in `TerraLifecycleTests`.
- 6 concurrency stress tests in `TerraLifecycleConcurrencyTests` (concurrent install, concurrent shutdown, interleaved start/shutdown, concurrent state reads).
- Verification: `swift test` passes all targets.

## Terra API 100% Readiness Execution (Phases 4-9) - 2026-03-03

- [x] Phase 4.0 preflight: fix `Terra.start()` overload ambiguity blocking test compilation.
- [ ] Phase 4.1 verify no internal `.run {}` usage outside deprecated compatibility shims/tests.
- [ ] Phase 4.2 verify no internal `.capture(...)` usage outside deprecated compatibility shims/tests.
- [ ] Phase 4.3 add API parity tests across closure-first vs builder-execute for all 6 span types.
- [ ] Phase 5.1 enforce explicit-first macro argument resolution with code comment + tests.
- [ ] Phase 5.2 add comprehensive macro expansion matrix (20+ cases).
- [ ] Phase 5.3 add import-minimal macro compile smoke test.
- [ ] Phase 6.1 gate exception message capture by privacy policy in all error recording paths.
- [ ] Phase 6.2 verify HMAC-SHA256 default coverage and keyed determinism tests.
- [ ] Phase 6.3 add privacy audit tests across all content-emitting call paths.
- [ ] Phase 6.4 verify OpenClaw disabled mode produces empty gateway hosts at start resolution.
- [ ] Phase 7.1 add Foundation Models tool-call capture via transcript diff + tests.
- [ ] Phase 7.2 add guardrail safety-check child spans + tests.
- [ ] Phase 7.3 add generation options capture on Foundation Models inference spans + tests.
- [ ] Phase 7.4 align MLX/Llama/FoundationModels wrapper metadata semantics + tests.
- [ ] Phase 8.1 rewrite README for canonical v3 API onboarding.
- [ ] Phase 8.2 add `Docs/Migration_Guide.md` (v1->v2->v3).
- [ ] Phase 8.3 add `Docs/API_Cookbook.md` with 8 copy-paste recipes.
- [ ] Phase 8.4 complete v3 unreleased `CHANGELOG.md` section.
- [ ] Phase 9.1 run full RC test/build matrix and strict concurrency check.
- [ ] Phase 9.2 deprecation sweep: annotations + forwarding + compatibility tests.
- [ ] Phase 9.3 run consistency grep checks (`.run`, `sha256Hex`, examples usage).
- [ ] Phase 9.4 add and complete `Docs/RC_CHECKLIST.md`.
- [ ] Phase 9.5 final RC qualification commit.

- [ ] **Phase 4: Fluent + Closure API Finalization**
- [ ] Ensure closure-first overloads are first-class in docs and examples; builders remain advanced mode.
- [ ] Keep `.run/.capture` deprecated shims but eliminate internal usage outside compatibility tests.
- [ ] Verify no behavior drift between closure-first and builder-execute paths.
- [ ] Exit criteria: API parity tests green for all span types.

- [ ] **Phase 5: Macro Reliability Pass**
- [ ] Reduce heuristic fragility: explicit arguments first, conservative auto-detection second.
- [ ] Add compile-focused regression tests for mixed parameter shapes and import-minimal files.
- [ ] Keep macro expansions dependency-light (no implicit import assumptions).
- [ ] Exit criteria: macro test matrix covers model/stream/agent/tool/embedding/safety + edge cases.

- [ ] **Phase 6: Privacy & Security Completion**
- [ ] Perform full privacy-policy audit over all front-facing call paths (manual spans, macros, wrappers, auto-instrumentation).
- [ ] Validate redaction behavior and content opt-in semantics with e2e tests.
- [ ] Verify no accidental content leakage in diagnostics/export paths.
- [ ] Exit criteria: privacy threat checklist signed off; tests enforce default-safe behavior.

- [ ] **Phase 7: Foundation Models / Wrapper Completion**
- [ ] Complete remaining `TerraFoundationModels` plan items (tool-call/transcript diff capture, guardrail safety spans, generation option capture).
- [ ] Align MLX/Llama/Foundation wrappers on consistent metadata and error semantics.
- [ ] Exit criteria: wrapper integration tests cover success/failure/streaming and metadata extraction.

- [ ] **Phase 8: Docs, Migration, and Developer UX**
- [ ] Rewrite README to lead with canonical API only; move legacy content to migration docs.
- [ ] Publish migration guide v3 with before/after examples and compatibility timeline.
- [ ] Add API cookbook snippets for common agent workflows (inference+tools+safety+streaming).
- [ ] Exit criteria: new user can instrument in <= 5 minutes using only README.

- [ ] **Phase 9: Release Qualification**
- [ ] Run full matrix: `swift build`, `swift test`, targeted stress/retry runs, strict concurrency build, lint/doc checks.
- [ ] Add release candidate checklist (semver decision, deprecation notes, changelog, examples validated).
- [ ] Gate release on zero known P1/P2 API issues.
- [ ] Exit criteria: RC sign-off checklist complete.

## Definition of Done (100% Ready)

- [ ] Single canonical front-facing API path with clear stability guarantees.
- [ ] Legacy APIs are deprecated (not primary), with documented removal timeline.
- [ ] Full test suite + stress/concurrency verification green and repeatable.
- [ ] Privacy defaults and diagnostics behavior are validated and documented.
- [ ] Migration docs and examples are fully aligned with the canonical API.
