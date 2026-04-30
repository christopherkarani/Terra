# Terra Codebase Audit And DX Review

- [x] Record baseline worktree state and preserve existing uncommitted user changes
- [x] Check project memory availability and document the limitation if unavailable
- [x] Verify SwiftPM/package bootstrap and capture any dependency or binary-target blockers
- [x] Audit Swift SDK correctness hotspots for privacy, lifecycle, streaming, and macro DX risks
- [x] Audit TraceKit ingestion/viewer reliability for coalescing, OTLP, and rendering edge cases
- [x] Audit profiler and native bridge contracts across CoreML, Power/Metal/ANE, Zig, and language bindings
- [x] Audit repo-level Developer Experience for CI coverage, scripts, docs, and generated artifact hygiene
- [x] Run targeted verification where local toolchains allow
- [x] Produce ranked findings with classification, impact, proposed fix shape, and verification command

## Baseline

- The worktree is already dirty before this audit. Existing edits in release/build files, TraceKit, Android, Zig, vendored binaries, and `.agents/` are treated as user-owned and must not be overwritten by the audit.
- Memory tooling is requested by project instructions, but no usable memory MCP/tool is exposed in this session after tool discovery. Audit notes will remain in `tasks/todo.md`.
- A prior Swift smoke check hung during third-party dependency checkout for SwiftProtobuf/protobuf rather than Terra source compilation; bootstrap reliability is part of this audit.

## Review

- Verification completed:
  - `swift package describe --type json` succeeded.
  - `swift test --target TerraHTTPInstrumentTests` failed immediately because this SwiftPM version does not accept `--target` for `swift test`; use `--filter` or `--skip`-based strategies instead.
  - `swift test --filter TerraHTTPInstrumentTests` and `swift test --filter DocumentationLintTests` both reached dependency resolution, then stalled while creating the `swift-protobuf` working copy and its protobuf submodules. The processes were stopped after reproducing the bootstrap blocker.
  - `zig build test --summary all` passed: 193/193 Zig tests.
  - `cd terra-rust && cargo test -- --test-threads=1` failed at link time: `../zig-core/zig-out/lib/libterra.a` contains archive members that `ld` reports are not Mach-O for the host link.
  - `python3 -m py_compile terra-python/terra.py` passed.
  - `cd terra-android && ./gradlew test assembleRelease` and `java -version` both failed because no Java runtime is installed in this environment.
  - `bash Scripts/validate_no_legacy_refs.sh` exited 0, but emitted repeated `rg` missing-file errors for stale `Docs/*` paths before printing success.
  - `git ls-files` did not show tracked `.DS_Store`, `.zig-cache`, `zig-out`, object files, `swiftdeps`, or `jniLibs` artifacts.
- Ranked findings:
  1. **Confirmed DX blocker: SwiftPM test commands are not reproducible from the approved plan.** `swift test --target ...` is rejected by SwiftPM, and the filter-based fallback repeatedly stalls while checking out `swift-protobuf` protobuf submodules. Impact: agents and humans cannot reliably validate Swift changes from a fresh or partially resolved checkout. Fix shape: replace target-form commands in docs/task templates with supported commands, add a bootstrap script that runs dependency resolution with clear timeout/failure messaging, and document/remediate the `swift-protobuf` submodule checkout requirement. Verify with `swift package resolve`, `swift test --filter TerraHTTPInstrumentTests`, and `swift test --filter DocumentationLintTests`.
  2. **Confirmed bug: Rust package does not link against the current Zig archive.** `cargo test -- --test-threads=1` fails because `terra-rust/build.rs` links `../zig-core/zig-out/lib/libterra.a`, whose archive members are not Mach-O for the macOS host. Impact: Rust SDK consumers cannot run tests from this checkout. Fix shape: make `build.rs` either build the Zig core for the host target before linking or validate the archive target and fail with a clear remediation; consider using a stable per-platform artifact path. Verify with `cd zig-core && zig build -Dtarget=aarch64-macos` followed by `cd terra-rust && cargo test -- --test-threads=1`.
  3. **Confirmed bug: Zig OpenTelemetry bridge does not install TaskLocal active context.** `TerraZigOTelBridge.withActiveSpan` starts a span and calls the operation, but `resolveParentContext()` only reads `TerraZigContext.activeSpanContext`; no code writes that TaskLocal. Impact: implicit child parenting through the Zig-backed tracer is suspect even though direct C parent-context tests pass. Fix shape: wrap the operation in `TerraZigContext.$activeSpanContext.withValue(span.zigContext)` for sync and async paths, then add a Swift integration test that creates nested Zig-backed spans without explicit parent pointers. Verify with `swift test --filter ZigBackendIntegrationTests`.
  4. **Confirmed ABI/documentation gap: SHA256 redaction exists in Zig but not in the public C header or bindings.** `zig-core/src/c_api.zig` accepts redaction value `3 => .sha256`, while `Sources/CTerraBridge/include/terra.h`, `zig-core/include/terra.h`, Rust, Android, and Python expose only drop/length/HMAC values. Impact: cross-language callers cannot intentionally select SHA256 and enum drift can break future bindings. Fix shape: add `TERRA_REDACT_SHA256 = 3` to headers/bindings and add an ABI contract test that compares exported constants across Zig/C/Rust/Python/Android. Verify with `zig build test --summary all`, `cargo test`, Python import tests, and Android unit tests.
  5. **Likely bug needing repro: explicit ended parents silently fall back to ambient context.** `Terra.withSpan` resolves `explicitParent.flatMap { $0.isEnded ? nil : $0.otelSpan } ?? Terra.currentSpan()...`, so `.under(endedParent)` inside another workflow can attach to the ambient workflow instead of surfacing misuse. Impact: trace trees can look valid while violating the caller's explicit parent intent. Fix shape: if `explicitParent` is non-nil and ended, throw or emit deterministic Terra guidance instead of falling back. Verify with a focused `.under(endedParent)` test inside an active workflow.
  6. **Likely bug needing repro: HTTP streaming errors drop partial streaming metrics.** `HTTPAIStreamingObserver.finishWithError` removes stream state without emitting chunk count, TTFT, or output-token attributes collected before the error. Impact: failed streams lose the exact diagnostics users need. Fix shape: finalize known stream metrics on error and add an error event/status without pretending the stream succeeded. Verify with delegate-backed SSE tests for chunk, error-after-chunk, and late delegate class registration.
  7. **Confirmed test gap / protocol bug: OTLP HTTP accepts duplicate `Content-Length` by using the first comma-separated value.** The hand parser combines duplicate headers, then uses the first token. Impact: conflicting lengths are not rejected, which can create ingestion ambiguity. Fix shape: reject duplicate or divergent `Content-Length` values with 400, while allowing identical duplicates only if intentionally supported. Verify with `OTLPHTTPServerTests` for duplicate matching/mismatching lengths, chunked, 100-continue, gzip, oversized header/body, and unsupported encoding.
  8. **Confirmed telemetry semantics gap: `terra.hw.gpu_occupancy_pct` stores a 0-1 fraction.** `TerraMetalProfiler.attributes(gpuUtilization:)` writes the same fractional value to `metal.gpu_utilization` and `terra.hw.gpu_occupancy_pct`; the key name says percent. Impact: TerraViewer and downstream dashboards can display a 64% workload as 0.64%. Fix shape: either multiply the canonical percent key by 100 or rename/add a fraction key with compatibility handling. Verify with `TerraMetalProfilerAttributeTests` and viewer classifier expectations.
  9. **Confirmed DX gap: `PowerMetricsCollector` fails silently when permissions/process startup fail.** The collector catches `proc.run()` errors and returns a zero summary later with no reason. Impact: users and agents cannot distinguish "no power draw" from "powermetrics unavailable/unauthorized." Fix shape: expose a start result or diagnostic status while preserving a compatibility wrapper if needed. Verify with tests that inject a failing process runner.
  10. **Likely bug / honesty gap: ANE profiler install reports success without collecting metrics.** The Objective-C bridge marks itself installed when `_ANEPerformanceStats` exists, but comments say actual swizzling is not implemented and metrics remain mostly static. Impact: users may trust ANE telemetry that is only an availability probe. Fix shape: separate `isAvailable` from `isCollecting`, make install report probe-only status, and update docs/tests. Verify with `TerraANEProfilerTests`.
  11. **Confirmed macro DX gap: non-literal `streaming:` expressions silently choose inference.** The macro only treats `streaming: true` as streaming; `streaming: someBool` expands to `Terra.infer`. Impact: coding agents can produce code that looks dynamic but traces the wrong operation. Fix shape: emit a diagnostic for non-literal streaming expressions or generate a conditional wrapper. Verify with `TracedMacroExpansionTests` for literal true, literal false, and non-literal streaming.
  12. **Confirmed docs/CI DX gap: validation and CI do not cover the real repo surface.** CI only runs SwiftLint, `swift test`, and API checks; it does not cover Zig, Rust, Android, Python, script validation, artifact drift, or docs validation. The legacy-reference script checks missing docs paths yet exits green. Impact: cross-language regressions already observed locally would not be caught before merge. Fix shape: add CI jobs or a staged validation script for Zig/Rust/Python/Android where toolchains are available, and make doc validation fail on missing scoped paths. Verify with CI and `bash Scripts/validate_no_legacy_refs.sh`.
- Residual limits:
  - Swift target tests could not complete because dependency checkout stalls before compilation.
  - Android tests could not run locally because Java is missing.
- Existing user-owned changes outside `tasks/todo.md` were not modified.

# Terra Framework DX Improvements

- [x] Record implementation plan and preserve the existing dirty worktree
- [x] Add one-command validation for human and coding-agent workflows
- [x] Add agent-facing source map
- [x] Add telemetry schema registry and validation
- [x] Add binding conformance matrix/checks
- [x] Add golden trace fixtures and tests
- [x] Add runtime environment diagnostics API
- [x] Add privacy audit mode
- [x] Turn docs/examples into executable validation where practical
- [x] Wire new checks into CI
- [x] Run available verification and document blocked toolchains

## Baseline

- The worktree is already dirty from the prior audit/remediation and user-owned changes. This pass must add focused files and avoid reverting existing edits.
- Memory tooling remains unavailable in this session despite project instructions requiring it.
- SwiftPM test execution remains vulnerable to dependency checkout stalls; new validation should report that clearly rather than hanging silently.
- Android execution remains locally blocked until a Java runtime is installed.

## Implementation Notes

- Primary goal: make framework contracts explicit and machine-checkable, especially for coding agents.
- Public runtime additions should be additive and avoid breaking existing API call sites.
- Generated/source-of-truth artifacts should live in `Docs/` or `Scripts/` and be cheap to validate locally.

## Review

- Added one-command validation in `Scripts/validate.sh` with quick/full modes. It runs docs hygiene, snippet validation, telemetry schema validation, binding conformance, Python syntax, Zig tests, Rust tests, SwiftPM manifest/tests, and Android checks when Java is actually usable.
- Added `Docs/AGENT_SOURCE_MAP.md` so coding agents can route common Terra changes to canonical source files and focused checks.
- Added `Docs/telemetry-schema.json` with 117 telemetry entries and `Scripts/validate-telemetry-schema.py` to enforce required fields, allowed types/stability values, duplicate JSON keys, and duplicate telemetry keys.
- Added `Docs/BINDING_CONFORMANCE.md`, `Scripts/validate-bindings.py`, and `Fixtures/trace-golden/canonical-ai-workflow.json` to lock down binding constants, feature parity, and a canonical workflow/inference/tool/streaming-error trace shape.
- Added additive runtime APIs:
  - `Terra.diagnoseEnvironment()` for structured tracing/provider/native/platform/tooling/ANE diagnostics plus recommended fixes.
  - `Terra.auditPrivacy(...)`, `Terra.auditCapturePolicy(...)`, and validation aliases for strict non-mutating privacy/capture audits.
- Added focused Swift tests for environment diagnostics and privacy audit behavior. Local SwiftPM test execution remains blocked before compilation by `swift-protobuf` submodule checkout stalls, matching the earlier audit blocker.
- Wired new cheap checks into CI repository validation. SwiftPM still runs through `Scripts/validate-swiftpm.sh`; Android CI now installs Java before Gradle validation.
- Verification completed:
  - `python3 Scripts/validate-doc-snippets.py`
  - `python3 Scripts/validate-telemetry-schema.py`
  - `python3 Scripts/validate-bindings.py`
  - `python3 Scripts/validate-bindings.py --matrix`
  - `Scripts/validate.sh --quick`
  - `git diff --check`
- Verification blocked or skipped:
  - Focused Swift tests for the new APIs are blocked locally by SwiftPM dependency working-copy creation for `swift-protobuf` nested submodules before Terra compilation starts.
  - Android Gradle validation is skipped locally because no Java runtime is installed.

# Release 0.3.2

- [ ] Confirm the release commit only contains the requested `swift-syntax` constraint relaxation plus release metadata
- [x] Update `Package.swift` to accept `swift-syntax` `600.0.0..<700.0.0`
- [ ] Run `swift package resolve`, `swift build`, and `swift test`
- [ ] Verify Terra co-resolves with Swarm in a real consumer scaffold
- [ ] Commit on `main` with the requested message
- [ ] Create and push annotated tag `0.3.2`

## Baseline

- The worktree is already dirty in unrelated files outside this release scope; those changes must stay out of the release commit.
- `Package.swift` currently pins `https://github.com/swiftlang/swift-syntax.git` with `from: "602.0.0"`.
- This patch release is intended only to unblock Swarm/Wax co-residency by widening Terra's `swift-syntax` constraint without changing any other package pins or source behavior.

## Review

- The requested manifest change is applied exactly once in `Package.swift`; no other package pin was changed.
- Macro compatibility was inspected against `swift-syntax 600.0.0`, and no concrete `602+`-only APIs were found in `Sources/TerraTracedMacroPlugin`, `Sources/TerraTracedMacro`, or the macro tests.
- Terra-alone dependency solving accepts the widened range and selects `swift-syntax 602.0.0`, which is expected when Terra is resolved without Swarm's tighter `600.x` constraint.
- In a real cloned Swarm consumer scaffold with the local Terra checkout added as a package dependency, SwiftPM's solver selected `swift-syntax 600.0.1`, which confirms the original Terra/Swarm range conflict is removed.
- Full `swift build` / `swift test` verification is currently blocked by a pre-existing clean-build issue unrelated to the `swift-syntax` change: `Package.swift` declares binary target `libtera`, while `Vendor/libtera.xcframework/Info.plist` exposes `libterra.a`, and SwiftPM rejects that artifact mapping on a clean build.
- Initial verification was also impeded by host disk exhaustion during dependency checkout; generated Xcode caches were cleared to restore free space, but the binary-target mismatch remains the release blocker.

# Release 0.2.4

# PR 23 Zig Lifecycle Fix

- [x] Review PR #23 against current `main` and identify stale/conflicting code paths
- [x] Integrate Zig lifecycle parity into current `main` without regressing provider feature gates
- [x] Add focused regression coverage for Zig idempotency/shutdown and persistence failure cleanup
- [x] Run focused lifecycle tests plus SwiftPM build/test validation
- [x] Push the fixed branch and update PR #23

## Baseline

- PR #23 is stale relative to `main` and conflicts in `Sources/Terra/Terra+OpenTelemetry.swift`, `Sources/Terra/TerraZigOTelBridge.swift`, and `Sources/TerraAutoInstrument/Terra+Start.swift`.
- Current `main` already has `_supportsZigBackend(_:)`, production ingest header wiring, service metadata resolution, profiler updates, and `shutdownZigBackend()`.
- The fix must preserve the current strict Zig capability gate and only add synchronized/idempotent Zig backend lifecycle handling plus regression coverage.

## Review

- Preserved current `main` startup behavior and kept `_supportsZigBackend(_:)` as the strict traces-only gate, so Zig does not silently drop metrics, logs, signposts, sessions, persistence, or sampling configuration.
- Added synchronized Zig backend state handling around `_zigInstance`; repeated install reuses the active instance, shutdown claims the instance under lock, performs native teardown outside the lock, and drives lifecycle state through shutting down to stopped.
- Extended test cleanup to shut down an active Zig backend, preventing cross-test runtime leakage.
- Added Zig integration regression coverage for idempotent install, lifecycle state parity, idempotent shutdown, and global test isolation.
- Strengthened persistence error mapping coverage to prove failed persistence startup leaves Terra stopped, non-running, and without installed OpenTelemetry configuration/providers.
- Validation completed:
  - `swift test --disable-automatic-resolution --scratch-path /Users/chriskarani/CodingProjects/RYNO/Terra/.tmp/release-032-clean/.build --filter 'ZigBackendIntegrationTests|TerraLifecycleAPITests|TerraLifecycleErrorMappingTests'`
  - `swift build --disable-automatic-resolution --scratch-path /Users/chriskarani/CodingProjects/RYNO/Terra/.tmp/release-032-clean/.build`
  - `zig build test --summary all` from `zig-core/`
  - `swift test --disable-automatic-resolution --scratch-path /Users/chriskarani/CodingProjects/RYNO/Terra/.tmp/release-032-clean/.build --parallel --num-workers 1`
- Residual warnings are pre-existing third-party SwiftPM plugin deprecations and existing deprecated API warnings in tests; all Terra build/test commands passed.

- [x] Confirm the exact diff to ship and keep unrelated TraceKit edits out of the release commit
- [x] Re-run targeted verification for the handoff/docs release payload
- [x] Commit the release payload on `main` and prepare it for push to `origin/main`
- [ ] Create GitHub release `0.2.4` and confirm public availability

## Baseline

- Repository visibility is already `PUBLIC` on GitHub (`christopherkarani/Terra`), so no repository visibility change is required.
- The worktree still contains unrelated pre-existing edits in `Sources/TerraTraceKit/TraceLoader.swift` and `Tests/TerraTraceKitTests/TraceKitTests.swift`; the release commit must not include them.
- The latest published git tag is `0.2.3`, so the next patch release for the handoff/docs work is `0.2.4`.
- The release payload was committed locally as `b66e913` (`docs: clarify span handoff lifecycle`) before the push/release steps.

## Verification

- `swift test --filter 'TerraManualTracingTests|TerraComposableAPITests|TerraStreamingSpanTests|TerraDXTests|TerraIdentifierTests|DocumentationLintTests|QuickstartRecipeSnippetTests'`
- The targeted suites passed; remaining warnings are unchanged third-party SwiftPM plugin warnings under `.build/checkouts`.

# Parent-Span Handoff And Stream Lifecycle Clarification

- [x] Make parent-span lifecycle rules explicit in public method comments and public docs
- [x] Add a safe deferred-tool handoff helper so later tool work does not depend on reusing an ended child span
- [x] Expose a clearer `withToolParent` / `handoff` public API for spans that outlive inference or stream child closures
- [x] Add regression coverage for ended-parent handoff failure, deferred tool execution, and stream/non-stream parentage
- [x] Run targeted verification and document the result

## Baseline

- The worktree was already dirty before implementation because of unrelated user changes in `Sources/TerraTraceKit/TraceLoader.swift` and `Tests/TerraTraceKitTests/TraceKitTests.swift`; this task avoids those files.
- Wax CLI is still unavailable in this environment (`waxmcp` not installed), so project memory capture remains blocked for this session.
- Before edits, Terra already had the right underlying lifecycle behavior for stream finalization and explicit parent spans, but the safe deferred-tool pattern was spread across docs, guidance, and internal knowledge rather than exposed as a clear public API.

## Review

- Added a public tool-first handoff surface in `TerraCore`:
  - `SpanHandle.handoff()`
  - `SpanHandle.withToolParent(_:)`
  - `ToolParentHandoff.tool(...)`
- The new handoff resolver reuses the nearest still-live workflow/manual parent for later tool execution and throws deterministic Terra guidance when no long-lived parent remains alive.
- Updated method comments in the manual/composable tracing APIs to make closure ownership explicit, clarify that child inference/stream spans end when their closure returns, and fix the previously swapped `Operation.run` overload documentation.
- Updated public docs and discovery guidance so the canonical deferred-tool example is now `try span.handoff().tool(...)` rather than only raw `.under(parent)` usage.
- Added regression coverage for:
  - deferred tool after non-stream inference
  - deferred tool after stream
  - handoff failure after the long-lived parent already ended
  - updated help/capabilities/guidance expectations for the new surface
- Verification completed:
  - `swift test --filter 'TerraManualTracingTests|TerraComposableAPITests|TerraStreamingSpanTests|TerraDXTests|TerraIdentifierTests|DocumentationLintTests'`
  - `swift test --filter 'TerraManualTracingTests|TerraDXTests|TerraIdentifierTests|DocumentationLintTests'`
- Residual warnings remain from pre-existing test code and third-party SwiftPM plugin sources under `.build/checkouts`; the new handoff/docs/regression work passed.

# Mission-Critical Audit And Remediation

- [x] Audit mission-critical paths in `TerraCore`, `TerraAutoInstrument`, `TerraHTTPInstrument`, `TerraTraceKit`, and `TerraCoreML`
- [x] Run focused build/test sweeps to surface correctness, concurrency, privacy, and lifecycle failures
- [x] Fix confirmed bugs with the smallest safe production-grade changes
- [x] Add or tighten regression coverage for every code bug fixed
- [x] Run final targeted verification and document residual risks

## Baseline

- Worktree is clean before this audit.
- Wax CLI is referenced by project instructions but `waxmcp` is not installed in this environment, so persistent memory capture is blocked for this session.
- Mission-critical areas for this pass are:
  - `Sources/Terra/*` for runtime, workflow/manual tracing, OpenTelemetry install, privacy propagation, and core span lifecycle
  - `Sources/TerraAutoInstrument/*` for startup/lifecycle configuration and exporter wiring
  - `Sources/TerraHTTPInstrument/*` for network interception, request parsing, streaming observers, and parent span linkage
  - `Sources/TerraTraceKit/*` for trace ingestion/storage/decoding, where corruption or ordering bugs would damage diagnostics
  - `Sources/TerraCoreML/*` for runtime instrumentation that uses method swizzling and asynchronous metrics capture

## Review

- Audited the highest-risk runtime paths in `TerraCore`, `TerraAutoInstrument`, `TerraHTTPInstrument`, `TerraTraceKit`, and `TerraCoreML` with emphasis on lifecycle correctness, parent-span linkage, sync/async bridging, and persistent diagnostics correctness.
- Fixed a stale-configuration bug in `HTTPAIInstrumentation`: the installed `URLSessionInstrumentation` closures previously captured the first host/openclaw configuration permanently, so later `Terra.reconfigure(...)` or shutdown-driven disable flows could silently keep instrumenting old hosts. The configuration closures now resolve live config on each use, and a regression test proves the matcher updates after runtime host changes.
- Fixed a mission-critical hang risk in `CoreMLInstrumentation`: synchronous compute-plan capture used an unbounded `DispatchSemaphore.wait()` plus unsynchronized detached-task mutation, which could block model-load instrumentation indefinitely and race the detached result handoff. The path now uses a locked result box plus a bounded timeout fallback that emits deterministic timeout telemetry instead of hanging.
- Added regression coverage for both bugs:
  - `HTTPAIInstrumentationTests.configurationClosuresObserveUpdates`
  - `TerraCoreMLTopLevelTests.synchronousComputePlanCaptureTimesOut`
- Verification completed:
  - `swift test --parallel --num-workers 1 --filter 'TerraLifecycleAPITests|TerraLifecycleErrorMappingTests|TerraSessionTests|TerraHTTPInstrumentTests|TerraTraceKitTests|TerraCoreMLTests|TerraOpenTelemetryInstallConcurrencyTests|TerraLifecycleConcurrencyTests|TerraConcurrencyPropagationTests|TerraStreamingSpanTests'`
  - `swift test --parallel --num-workers 1 --filter 'HTTPAIInstrumentationTests|TerraCoreMLTopLevelTests|TerraLifecycleAPITests|TerraHTTPInstrumentTests'`
  - `swift test --parallel --num-workers 1`
- Residual limits after this pass:
  - Wax memory persistence remains unavailable in this environment because `waxmcp` is not installed.
  - Third-party SwiftPM plugin warnings remain under `.build/checkouts`; the Terra-owned targets and tests passed after the fixes.

# Terra Workflow-First Breaking Cleanup

- [x] Replace the `trace` / `agentic` / `loop` root surface with `Terra.workflow(...)` and `Terra.workflow(..., messages:)`
- [x] Collapse the public annotation handle surface onto `SpanHandle` and remove `TraceHandle` from the public path
- [x] Remove `ModelID`, `ToolCallID`, `callID:`, and other compatibility-only public overloads
- [x] Move child workflow helpers onto `SpanHandle` and add transcript support via `WorkflowTranscript`
- [x] Rename root telemetry rollups from `terra.agent.*` to `terra.workflow.*` and stop marking generic roots as `invoke_agent`
- [x] Rewrite discovery/docs/examples/tests to the workflow-first API only
- [x] Run targeted Swift build/test verification, fix regressions, and document results below

## Baseline

- The worktree is clean before implementation.
- The current public docs and discovery surface still teach `trace`, `agentic`, `loop`, and compatibility notes for `TraceHandle`, `ModelID`, and `ToolCallID`.
- The cookbook currently contains invalid `agent.tool(...).run { ... }` call sites that do not match the actual `AgentHandle` API and will be removed as part of the rewrite.
- Session-memory capture was attempted via Wax CLI, but the discovered `/opt/homebrew/bin/waxmcp` entry is not executable in this environment.

## Review

- Replaced the root tracing entry points with `Terra.workflow(name:id:_:)` and `Terra.workflow(name:id:messages:_:)`, and removed the legacy `trace`, `agentic`, `loop`, and builder compatibility surface.
- Unified the public span mutation model on `SpanHandle`, added child helpers (`infer`, `stream`, `tool`, `embed`, `safety`, `agent`), and added `WorkflowTranscript` for buffered message mutation with writeback on success and failure.
- Removed `TraceHandle`, `AgentHandle`, `AgentLoopScope`, `ModelID`, `ToolCallID`, and `callID:`-only compatibility overloads from the public workflow path; `Operation.run` now exposes `SpanHandle`.
- Rewrote discovery, README, cookbook, DocC, sample code, and playground scenarios so the canonical path is `workflow -> child operations -> startSpan` with no legacy naming in the public docs.
- Renamed workflow rollups from `terra.agent.*` to `terra.workflow.*`, stopped treating generic roots as `invoke_agent`, and preserved child operation semantics.
- Hardened composable span execution so `.run { span in ... }` always sees a real Terra-managed span handle; the public composable API no longer depends on the synthetic test-handle seam.
- Updated and expanded regression coverage across manual tracing, composable operations, doc linting, macro expansion/import, HTTP span linkage, transcript handling, and workflow rollups.
- Verification completed:
  - `swift test --filter 'TerraComposableAPITests|TerraIdentifierTests|TerraProtocolSeamsTests|TerraManualTracingTests|TerraLoopAndPlaygroundTests|TerraAgentContextTests|TerraDXTests|TerraErrorRemediationTests|DocumentationLintTests|QuickstartRecipeSnippetTests|HTTPAIInstrumentationSpanLinkageTests|TracedMacroExpansionTests|TracedMacroImportSmokeTests'`
  - `swift test --parallel --num-workers 1 --filter 'TerraAPIParityTests|TerraClosureAPITests|TerraFluentAPITests|TerraLegacyClosureDeprecationTests|TerraTraceProtocolTests|TracedMacroPrivacyTests'`
  - `swift test --parallel --num-workers 1 --filter 'TerraConcurrencyPropagationTests|TerraLifecycleConcurrencyTests|TerraLifecycleTests|TerraOpenTelemetryInstallConcurrencyTests|TerraSharedSessionTests|TerraMetricsTests'`
  - `swift test --parallel --num-workers 1 --filter 'TerraE2ETests|TerraPrivacyAuditTests|TerraPrivacyE2ETests|TerraPrivacyV3Tests|TerraRedactionPolicyTests|TerraInferenceSpanTests|TerraStreamingSpanTests|TerraSpanTypesTests|TerraTraceableTests|TerraInstrumentationNameTests|TerraInternalConstantsTests|TerraKeyV3Tests|TerraLlamaWrapperTests|ZigBackendIntegrationTests'`
  - `swift test --parallel --num-workers 1`
- Residual warnings remain in third-party SwiftPM plugin sources under `.build/checkouts/grpc-swift` and `.build/checkouts/swift-protobuf`; Terra-owned targets passed verification.

# Terra HTTP and Manual Span Unification

- [x] Add Terra-owned structured prompt/message keys and request plumbing for explicit inference spans
- [x] Update manual tracing to support attribute introspection, ended-span detached fallback, and `AgentHandle.infer(messages:)`
- [x] Update HTTP auto-instrumentation to parent spans under active Terra spans and inherit agent operation metadata
- [x] Extend HTTP request parsing and prompt semantic enrichment for message-based requests
- [x] Add Terra-owned streaming chunk tracking for HTTP AI streaming responses
- [x] Add or update focused tests for HTTP parent linkage, operation inheritance, prompt semantics, detached fallback, and structured messages
- [x] Run `swift build` after each file cluster and finish with targeted test verification

## Baseline

- `swift build` currently emits pre-existing warnings from third-party SwiftPM plugin sources under `.build/checkouts/grpc-swift` and `.build/checkouts/swift-protobuf` before Terra targets compile.
- This task remains Terra-only. Verification must not introduce new Terra-owned warnings or errors; third-party plugin warnings are baseline and will be reported, not fixed.

## Review

- Implemented all six requested fixes in Terra-owned sources only.
- Added focused coverage for HTTP parent linkage, parser message extraction, ended-span detached fallback, and structured-message inference.
- Final `swift build` succeeds. Remaining warnings come from SwiftPM plugin sources under `.build/checkouts`, which are outside Terra-owned code.

# Terra API Consolidation And Discovery Refresh

- [x] Unify the public span-annotation story around `SpanHandle` and keep `TraceHandle` as a compatibility wrapper
- [x] Add `Terra.loop(name:id:messages:_:)` with buffered message mutation that remains Swift 6-sendability friendly
- [x] Deprecate `TraceBuilder` in favor of `Terra.trace(name:id:_:)` and `Terra.startSpan(name:id:attributes:)`
- [x] Add `Terra.help()` and thread discovery hints through diagnostics and structured Terra errors
- [x] Expand built-in guides and examples to cover the canonical trace-first workflows at much higher breadth
- [x] Add a lightweight `Terra.playground()` example runner for local discovery
- [x] Update DocC and website guidance so `Terra.trace` is the primary mental model and `Operation` is secondary
- [x] Run targeted Terra and TerraViewer verification for API, DX, loop behavior, discovery, and hardware classification

## Baseline

- The current public surface already includes `Terra.trace`, `Terra.startSpan`, `Terra.agentic`, `Terra.infer/stream/embed/tool/safety`, `TraceHandle`, `SpanHandle`, and `TraceBuilder`; this task reduces conceptual overlap without breaking source compatibility.
- TerraViewer already classifies `terra.exec.route.*` and `terra.espresso.*` as hardware telemetry. Viewer edits are only justified if verification shows a regression.
- ANE hardware metrics already emit both legacy and canonical keys, including the deliberate legacy microseconds / canonical milliseconds dual emission.

## Review

- `SpanHandle` is now the primary Terra-owned span annotation surface, with token and response-model helpers added directly on the handle. `TraceHandle` remains public for `Operation.run { ... }` call sites but now bridges into the active Terra span when Terra owns it.
- Added `Terra.loop(name:id:messages:_:)` with `AgentLoopScope` and buffered transcript mutation APIs (`snapshotMessages`, `replaceMessages`, `appendMessage`, `appendMessages`, `clearMessages`) so Swift 6 `@Sendable` closures can still update caller-owned chat transcripts.
- Deprecated `TraceBuilder` and the builder-style `Terra.trace(name:)` entry point in favor of the explicit trace-first roots: `Terra.trace`, `Terra.loop`, `Terra.agentic`, and `Terra.startSpan`.
- Discovery now has a first-class start-here path: `Terra.help()` plus expanded capabilities, guides, examples, `ask(_:)`, richer `diagnose()` suggestions, and TerraError remediation that points users back to `help`, `ask`, and `examples`.
- Added `Terra.playground()` with guided local scenarios for trace, loop, agentic, stream, manual-parent, and diagnostics workflows.
- Updated DocC and the landing page to present `quickStart -> help -> diagnose -> trace/loop/agentic/startSpan` as the canonical progression, while keeping the operation helpers documented as secondary.
- Verification completed:
  - `swift build --target TerraCore`
  - `swift test --filter TerraDXTests --filter TerraIdentifierTests --filter TerraLoopAndPlaygroundTests`
  - `swift test --filter TraceTelemetryFocusTests --filter DashboardViewModelTests --filter TraceViewModelTests --filter TraceTimelineCanvasViewTests --filter DashboardSessionBuilderTests` in `TerraViewer`
  - `npm ci`, `npm run lint`, and `npm run build` in `website/`
- Residual warnings remain external to the implementation:
  - SwiftPM plugin deprecation / Sendable warnings from third-party checkouts under `.build/checkouts`
  - Next.js workspace-root warning during `website` build because multiple `package-lock.json` files exist above the app directory

# Terra SDK Skill Creation

- [x] Create a project-local `terra-sdk` skill with source-of-truth guidance for tracing, tree visualization, and telemetry
- [x] Add reference docs for source selection, Viewer tree rules, metrics mapping, and hotspot patterns
- [x] Validate the generated skill metadata and folder structure
- [x] Remove duplicate reference files so the skill has one canonical doc per topic

## Review

- Created `.codex/skills/terra-sdk/SKILL.md` as the primary skill entry point and generated `agents/openai.yaml` for launcher metadata.
- Added canonical reference docs under `.codex/skills/terra-sdk/references/` for source-of-truth selection, tree visualization, metrics, and hotspot patterns.
- Ran `quick_validate.py` successfully after the skill and reference docs were assembled.
- Added a TerraViewer contract plus an emission matrix so agents know the exact span-to-surface requirements for Mission Control and TraceTree.
- Clarified resource-vs-span identity placement, content redaction fallback behavior, and TerraViewer smoke-test verification steps.
- Added explicit naming conventions so agents choose meaningful session/root/agent/tool/model labels instead of generic defaults.

# Terra Codebase Audit Remediation

- [x] Preserve the dirty worktree baseline and avoid reverting user-owned edits
- [x] Fix explicit ended-parent fallback so child spans do not silently attach to ambient workflow spans
- [x] Fix Zig-backed active-span propagation for sync and async `withActiveSpan`
- [x] Preserve partial HTTP streaming metrics and mark stream spans failed on transport errors
- [x] Reject conflicting or comma-joined `Content-Length` headers in OTLP HTTP ingestion
- [x] Normalize Metal GPU occupancy percentage units
- [x] Report PowerMetrics start status instead of silently swallowing launch failures
- [x] Separate ANE probe availability from active metric collection
- [x] Reject non-literal `@Traced(streaming:)` values with an explicit diagnostic
- [x] Add SHA256 redaction enum coverage consistently across C/Zig/Rust/Python/Android bindings
- [x] Make Rust tests rebuild `libterra.a` for Cargo's host target
- [x] Add a supported SwiftPM validation script with timeout diagnostics for dependency checkout stalls
- [x] Refresh docs validation scope and add CI coverage for docs, Zig, Rust, Python, and Android checks
- [x] Add focused regression tests for the Swift fixes where local test scaffolding exists

## Baseline

- The worktree was already dirty before this remediation. Pre-existing user-owned edits included release/build script changes, `TraceLoader`/TraceKit test changes, Android bridge/runtime changes, Zig C API changes, vendored `libtera.xcframework` changes, and `.agents/`.
- Project instructions request memory tooling, but no usable memory tool is exposed in this session. This limitation remains recorded rather than simulated.
- SwiftPM bootstrap reliability remains a live local blocker: focused `swift test` runs reach dependency working-copy creation and then stall inside `swift-protobuf` submodule clones (`abseil-cpp` / `protobuf`) before Terra test compilation starts.
- Local Android verification is blocked by the missing Java runtime on this machine.

## Review

- Fixed confirmed runtime bugs in Terra-owned sources:
  - explicit ended parents now call `setNoParent()` and emit `terra.parent.explicit_ended` telemetry instead of falling back to the ambient active span
  - the Zig OpenTelemetry bridge now binds Terra's task-local Zig context while sync and async active spans run
  - HTTP streaming completion errors now preserve observed chunk/token metrics, set failed span status, and emit `stream.error`
  - OTLP HTTP ingestion now rejects conflicting duplicate `Content-Length` headers and comma-joined values
  - Metal occupancy now reports the canonical percentage value (`64.0` for `0.64` utilization)
  - PowerMetrics start now exposes `StartResult` / `lastStartResult`
  - ANE profiler now distinguishes API availability from active collection hooks
  - `@Traced(streaming:)` now errors on runtime expressions instead of silently treating them as non-streaming
- Fixed cross-language/DX gaps:
  - `TERRA_REDACT_SHA256` is now represented in C, Zig, Rust, Python, and Android binding layers
  - `terra-rust/build.rs` now builds the Zig core for Cargo's host target unless `TERRA_LIB_DIR` is supplied
  - `Scripts/validate-swiftpm.sh` now runs manifest, dependency resolution, and supported `swift test` invocations with timeout diagnostics for SwiftPM/git checkout stalls
  - legacy-reference validation now scans existing canonical docs/snippets and fails clearly on missing scan roots
  - CI now runs docs validation, timeout-bounded SwiftPM validation, Zig tests, Rust tests, Python syntax checking, and Android Gradle validation with Java 17
- Local verification completed:
  - `bash Scripts/validate_no_legacy_refs.sh`
  - `bash -n Scripts/validate-swiftpm.sh Scripts/validate_no_legacy_refs.sh`
  - `python3 -m py_compile terra-python/terra.py`
  - `zig build test --summary all`
  - `cd terra-rust && cargo test -- --test-threads=1`
  - `swift package describe`
- Local verification blocked:
  - `swift test --filter explicitEndedParentDoesNotFallBackToAmbientWorkflow` stalled while cloning `swift-protobuf` submodules before compiling Terra tests
  - `swift test --skip-update --filter explicitEndedParentDoesNotFallBackToAmbientWorkflow` hit the same `swift-protobuf` submodule clone stall
  - `cd terra-android && ./gradlew test assembleRelease` is blocked because this machine has no Java runtime installed
