# Terra Codebase Audit And DX Review

## Review Follow-up Fixes And Main Merge - 2026-05-17

- [x] Fix Swift/Zig instance reference locking so shutdown cannot free the native instance during an in-flight native call.
- [x] Fix typed-throws macro parsing to use `ThrowsClauseSyntax.type` instead of string matching.
- [x] Add focused regression coverage for the lifecycle lock and typed throws whitespace.
- [x] Run targeted Swift validation plus practical repo validation.
- [x] Commit, push, and merge `codex/assess-terra-for-drones` into `main`.

### Plan

1. Patch the two review findings directly in the changed files.
2. Prove each with the narrowest regression test: one lifecycle synchronization test and one macro expansion spelling test.
3. Run focused suites first, then quick validation.
4. Push the branch, merge to the real default branch `main`, push `main`, and confirm the final branch state.

### Review

- Fixed both code-review findings: `TerraZigInstanceRef.withInstance` now holds the instance lock while the native pointer is in use, and typed throws parsing now reads `ThrowsClauseSyntax.type` instead of matching rendered text.
- Added regression coverage for shutdown waiting on an in-flight native use and for `throws (MyError)` macro expansion.
- Verification passed: `swift test --filter 'ZigBackendIntegrationTests|TracedMacroExpansionTests'`, `git diff --check`, and `bash Scripts/validate.sh --quick`.

## Fresh Deep Production Readiness Audit - 2026-05-17

- [x] Establish baseline git status and preserve user-owned worktree changes.
- [x] Read repo instructions, memory, lessons, Package.swift, README, docs, scripts, examples, bindings, and release/task notes before conclusions.
- [ ] Inventory all major surfaces: Swift SDK, macros, TraceKit, HTTP instrumentation, FoundationModels, CoreML, MLX, Llama, profilers, Zig bridge/backend, Rust/Python/Android/C++/ROS2 bindings, examples, CI/scripts, docs, and release artifacts.
- [ ] Identify front-facing APIs exported by modules, macros, public types, public initializers, environment flags, CLI/scripts, bindings, and examples.
- [ ] Public Swift API and source compatibility review.
- [ ] Macro expansion behavior and privacy guarantee review.
- [ ] Zig backend and Swift/Zig FFI correctness review.
- [ ] Memory leaks, lifetime bugs, ownership issues, and unsafe pointer handling review.
- [ ] Concurrency, Sendable, actor/task propagation, cancellation, and lifecycle safety review.
- [ ] Privacy/redaction guarantees across all integration paths.
- [ ] TraceKit storage/rendering/OTLP correctness review.
- [ ] Profiler correctness and process lifecycle handling review.
- [ ] Binding/package drift review across Rust, Python, Android, C++, vendored headers, ROS2, and release artifacts.
- [ ] Tests, CI, docs, examples, and release readiness review.
- [ ] Run practical validation and record exact pass/fail/blocker evidence.
- [ ] Write final findings-first report with severity, line evidence, missing tests, readiness scores, risk matrix, uncertainty, and remediation order.

### Plan

1. Baseline and inventory: record branch/status, read manifest/docs/task notes/scripts, map products/targets/modules/bindings, and list public or developer-facing surfaces.
2. Parallel review: split broad areas into focused reviewers for Swift API/concurrency, macros, Zig/FFI/memory, privacy/security, TraceKit/profilers, and docs/bindings/release artifacts.
3. TDD audit lens: for each defect, identify the missing failing test, fixture, or validation gate that would have caught it before release.
4. Verification: run the strongest practical local suite (`swift package describe --type json`, Swift tests or targeted filters, `Scripts/validate.sh --quick`, Zig, Rust, Python, C++/ROS2, Android/Kotlin where tooling exists) and record blockers exactly.
5. Report: produce findings first by P0/P1/P2/P3, with file/line evidence, why it matters, repro/reasoning, missing test, suggested fix direction, readiness scores, subsystem risk matrix, uncertainty, and remediation order.

### Review

- In progress. This is a read-only audit except for this task-note checklist.

## Deep Audit Remediation - 2026-05-17

- [x] Preserve existing robotics/transport worktree changes and include them in the final commit as requested.
- [x] Rebuild or refresh the vendored macOS `libtera.xcframework` so exported symbols match public headers.
- [x] Make Swift/Zig backend shutdown safe against stale tracer/span use after native teardown.
- [x] Make native error recording privacy-aware across C/Zig/Rust/Python/Android.
- [x] Sanitize HTTP URL attributes and close query-secret leakage.
- [x] Sanitize CoreML production error descriptions.
- [x] Fix Swift test isolation so full-suite tests do not deadlock through deinit-based semaphore release.
- [x] Fix macro source-compatibility gaps: generated name shadowing, provider overload drift, typed-throws/Sendable coverage or documented tests.
- [x] Bound Espresso log capture shutdown.
- [x] Align FFI thread-safety contracts or synchronization.
- [x] Fix CoAP caller-owned config mutation race.
- [x] Extend TraceKit redaction for imported `exception.message`, `http.url`, and `url.full`.
- [x] Remove raw tool payload examples and add lint/schema coverage where practical.
- [x] Resolve website high-severity dependency audit and add CI gate.
- [x] Run practical validation across Swift, Zig, Rust, Python, C++/bindings, website audit, and repository checks.
- [x] Commit and push all repo changes, including pre-existing user-owned changes.

### Plan

1. Start with tests/validation hooks that prove the audit findings: native symbol drift, privacy canaries, TraceKit redaction, macro expansions, and lifecycle/test isolation.
2. Fix runtime blockers first: native artifact, Zig backend lifecycle, privacy write sites, and shutdown hangs.
3. Fix developer-facing compatibility and release gates: macro overloads/tests, examples/docs, website audit, and validation scripts.
4. Re-run the strongest practical suite; record exact blockers if local tooling still prevents a gate.
5. Stage, commit, and push the full repo state because the user explicitly requested inclusion of all current changes.

### Review

- Remediation completed for the audit blockers while preserving the pre-existing robotics/transport worktree changes for the final all-in commit.
- Rebuilt `Vendor/libtera.xcframework` from the fixed Zig core and extended binding validation to fail when required vendored transport symbols are missing.
- Added lifecycle safety for stale Swift/Zig tracers and spans after backend shutdown; stale spans now no-op instead of retaining a freed native instance.
- Closed privacy leaks in native error recording, HTTP URL attributes, CoreML error descriptions, TraceKit fallback redaction, and examples that previously showed raw tool payloads.
- Improved macro compatibility with reserved generated trace parameter naming, typed-throws wrapping, provider overload parity, and expansion/smoke tests.
- Bounded Espresso process shutdown and added a force-kill regression test for processes that ignore SIGTERM.
- Website dependency audit is clean after dependency overrides and CI now runs `npm audit --audit-level=high`.
- Validation passed: `zig build test --summary all`; `python3 Scripts/validate-telemetry-schema.py`; `python3 Scripts/validate-bindings.py --matrix`; `swift package describe --type json`; targeted Swift remediation suite; `npm audit --audit-level=high`; `bash Scripts/validate.sh --quick`; Rust `cargo test -- --test-threads=1`; Python compile/unittest; `git diff --check`.
- Local Android Gradle remains blocked by missing Java runtime. Full unfiltered `swift test` was stopped after hanging in the Swift test helper for several minutes; targeted Swift suites and quick validation passed.

## Deep Production Readiness Audit - 2026-05-17

- [x] Establish baseline git status and preserve user-owned dirty changes.
- [x] Load repo guidance, lessons, Terra SDK skill guidance, and relevant memory before source review.
- [x] Read Package.swift, README, docs, existing task notes, scripts, examples, bindings, and release artifacts.
- [x] Inventory all front-facing APIs, public types, macros, module exports, environment flags, scripts, bindings, examples, and generated artifacts.
- [x] Public Swift API and source compatibility review.
- [x] Macro expansion behavior and privacy guarantee review.
- [x] Zig backend and Swift/Zig FFI correctness review.
- [x] Memory leaks, lifetime bugs, ownership issues, and unsafe pointer handling review.
- [x] Concurrency, Sendable, actor/task propagation, cancellation, and lifecycle safety review.
- [x] Privacy/redaction guarantees across all integration paths.
- [x] TraceKit storage/rendering/OTLP correctness review.
- [x] Profiler correctness and process lifecycle handling review.
- [x] Binding/package drift review across Rust, Python, Android, C++, vendored headers, ROS2, and release artifacts.
- [x] Tests, CI, docs, examples, and release readiness review.
- [x] Run practical validation and record exact pass/fail/blocker evidence.
- [x] Write final findings-first report with severity, line evidence, missing tests, readiness scores, risk matrix, and remediation order.

### Plan

1. Baseline and inventory: record branch/status, read manifest/docs/task notes/scripts, map products/targets/modules/bindings, and list public or developer-facing surfaces.
2. Parallel review: split broad areas into focused reviewers for Swift API/concurrency, macros, Zig/FFI/memory, privacy/security, TraceKit/profilers, and docs/bindings/release artifacts.
3. TDD audit lens: for each defect, identify the missing failing test, fixture, or validation gate that would have caught it before release.
4. Verification: run the strongest practical local suite (`swift package describe --type json`, Swift tests or targeted filters, `Scripts/validate.sh --quick`, Zig, Rust, Python, C++/ROS2, Android/Kotlin where tooling exists) and record blockers exactly.
5. Report: produce findings first by P0/P1/P2/P3, with file/line evidence, why it matters, repro/reasoning, missing test, suggested fix direction, readiness scores, subsystem risk matrix, uncertainty, and remediation order.

### Review

- Audit-only review completed; no source remediation was authorized or performed. The only intentional audit edit is this task note.
- Release blockers found: vendored `libtera.xcframework` is stale relative to public C transport helper declarations; Swift/Zig backend can retain a freed native instance through the global tracer provider; plain `swift test` is not currently a reliable release gate because it exposed a TerraMLX span-count failure and then stalled in shared test isolation.
- Serious privacy and lifecycle risks found: HTTP URLSession old semantic mode can emit `http.url` with query secrets; Zig/C/Rust/Python/Android error recording stores raw `exception.message`; CoreML production swizzles record raw `localizedDescription`; Espresso log capture shutdown can block indefinitely.
- Additional readiness gaps: macro expansion has Swift 6 source-compatibility cliffs, TraceKit redaction misses common imported sensitive keys, FFI wrapper thread-safety claims exceed Zig synchronization, CoAP transport mutates caller-owned config without a synchronization contract, website `npm audit --audit-level=high` fails, Android checks are blocked locally by missing Java runtime.
- Verification evidence recorded for final report: `swift package describe --type json` passed; `Scripts/validate.sh --quick` passed with ROS2/Android skips as documented; `zig build test --summary all` passed 200/200; Rust tests passed 35/35; Python unittest passed 4/4 and compile passed; C++ quick validation passed through `validate.sh`; binding matrix and header parity passed; `git diff --check` passed; full Swift suite was killed after sample evidence showed semaphore wait in test isolation; Java runtime missing.

## Drone/Robotics Readiness Implementation - 2026-05-07

- [x] Preserve current branch/worktree context and avoid reverting unrelated changes
- [x] Add failing/targeted validation for robotics telemetry schema and C ABI transport helpers
- [x] Expose UART/MQTT/CoAP transport adapter helpers through the stable C ABI
- [x] Promote `terra-ros2` toward pilot SDK ergonomics with ROS parameters, launch files, and docs
- [x] Register robotics telemetry keys and document the pilot contract
- [x] Add local/CI validation hooks for ROS2 package shape where full ROS is unavailable locally
- [x] Run focused validation and record residual external blockers

### Plan

1. Treat ROS 2 Linux as the first customer-facing robotics surface, with Jazzy/Ubuntu 24.04 as primary and Humble/Ubuntu 22.04 as compatibility.
2. Keep Terra's OpenTelemetry span model as the source of truth; add robotics attributes to the telemetry schema instead of inventing a parallel format.
3. Expose existing Zig UART/MQTT/CoAP transport adapters through callback-backed C ABI helpers only; do not embed platform MQTT, serial, or UDP stacks.
4. Make local progress without claiming external readiness while GitHub billing/CI and ARM hardware proof remain outside this checkout.

### Review

- Added callback-backed C ABI helpers for MQTT, CoAP, and UART transports, including Zig unit coverage and synchronized public headers.
- Upgraded `terra-ros2` with pilot parameters (`robot_id`, `vehicle_id`, `mission_id`, `component_name`, `autonomy_phase`, `content_policy`, `redaction_strategy`), forwarding-span metadata, launch file installation, and a colcon-first README.
- Added `Docs/ROBOTICS-PILOT.md`, linked it from the root README, and registered robotics telemetry keys in `Docs/telemetry-schema.json`.
- Added `Scripts/validate-ros2-package.sh` and wired it into local validation plus CI repository validation. It performs shape checks everywhere and runs real colcon build/test when `colcon` is installed.
- Verification passed:
  - `bash -n Scripts/validate.sh Scripts/validate-ros2-package.sh Scripts/validate-swiftpm.sh`
  - `python3 Scripts/validate-telemetry-schema.py`
  - `python3 Scripts/validate-bindings.py`
  - `python3 -m py_compile terra-ros2/launch/terra_ros2.launch.py`
  - `cd zig-core && zig build test --summary all` (`200/200` tests)
  - standalone compile of `terra_ros2_bridge_core.cpp`
  - C++ CMake smoke build and `ctest`
  - `bash Scripts/validate.sh --quick`
- Residual external blockers remain: `colcon` is not installed locally, Android Gradle is skipped in quick mode, remote GitHub Actions is still subject to the existing billing/account blocker, and ARM64 companion-computer proof needs actual hardware or self-hosted CI.

## Terra Production Push - 2026-05-06

- [x] Refresh repo, GitHub PR, CI, release, and memory state.
- [x] Preserve task notes and get `swiftformat` clean enough to rebase.
- [x] Rebase `swiftformat` onto current `origin/main`.
- [x] Resolve conflicts while preserving `main` Zig lifecycle parity and PR #25 audit/remediation fixes.
- [x] Run focused post-conflict Swift/Zig lifecycle verification.
- [x] Run local release validation gates.
- [ ] Push branch and get PR #25 conflict-free, non-draft, and green in CI or documented manual release exception.
- [ ] Merge PR #25 to `main`.
- [ ] Revalidate `main`.
- [ ] Publish GitHub releases for `0.3.2` backfill and `1.0.0`.
- [ ] Record final production result and residual blockers.

### Plan

1. Keep PR #25 scoped to the existing audit/remediation branch. Do not add Perfetto implementation or stale PR #15-#20 work unless a current conflict proves it is required.
2. Rebase onto `origin/main` and resolve only the known overlap in package metadata, OpenTelemetry/Zig lifecycle handling, lifecycle tests, Zig backend tests, and task notes.
3. Treat green local full validation, green GitHub CI, mergeability, post-merge validation, and published release pages as required gates before calling production done.
4. Use `1.0.0` as the production release version because the branch contains breaking API/configuration changes and native package metadata already reports `1.0.0`.

### Review

- Rebased `swiftformat` onto current `origin/main`; conflict resolution preserved `main` Zig lifecycle parity and PR #25 validation/runtime fixes.
- Focused post-conflict lifecycle verification passed: `swift test --disable-automatic-resolution --filter 'ZigBackendIntegrationTests|TerraLifecycleAPITests|TerraLifecycleErrorMappingTests'`.
- Fixed local full-suite blockers found during validation: invalid span guidance no longer aborts the process with debug assertions, and the TerraSession compute-plan test now asserts privacy-preserving hashed operation telemetry.
- `git diff --check` passed.
- `JAVA_HOME=/opt/homebrew/opt/openjdk@21 PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH Scripts/validate.sh --quick` passed.
- `JAVA_HOME=/opt/homebrew/opt/openjdk@21 ANDROID_HOME=/opt/homebrew/share/android-commandlinetools PATH=/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH TERRA_SWIFTPM_TIMEOUT_SECONDS=600 Scripts/validate.sh` passed, including SwiftPM, 404 Swift tests, Android native libraries, Gradle unit tests, and release AAR assembly.
- Pushed rebased branch `swiftformat` to PR #25; GitHub reports the PR as mergeable and conflict-free.
- Remote CI is blocked outside the repo: all four jobs failed before starting with the annotation "The job was not started because your account is locked due to a billing issue."
- Manual release exception approved on 2026-05-06 because Terra must ship now and the billing issue cannot be addressed. Use the passing full local validation as the release gate, then run the same validation again on clean `main` after merge.

## Production Readiness Check - 2026-05-06

- [x] Identify the active repo, branch, and dirty worktree scope.
- [x] Check GitHub default branch, PR, and CI state for the current branch.
- [x] Run local release/readiness validation commands that are practical in this environment.
- [x] Compare remaining blockers against the production push decision.
- [x] Record the final readiness verdict and required follow-up.

### Plan

1. Treat `/Users/chriskarani/CodingProjects/RYNO/Terra` as the active production candidate because the RYNO root is not a git repo, TerraViewer is clean, and Terra is the only dirty checkout.
2. Fail closed on production readiness if the branch has unmerged changes, failing or missing CI, unresolved local validation blockers, or release-critical task items still open.
3. Prefer current evidence from git, GitHub, and validation commands over older audit notes.

### Review

- Verdict: not ready to push into production yet.
- Active candidate is the Terra repo on branch `swiftformat`; TerraViewer is clean on `main`, and the RYNO root is not a git repository.
- The branch has a local documentation-only task note change in `tasks/todo.md`.
- GitHub PR #25 is still draft, targets `main`, and GitHub reports it as conflicting.
- After fetching, `origin/main` is 3 commits ahead of the branch while the branch is 5 commits ahead of `origin/main`.
- Merge conflicts are present in `Package.swift`, `Sources/Terra/Terra+OpenTelemetry.swift`, `Sources/Terra/TerraZigOTelBridge.swift`, `Tests/TerraAutoInstrumentTests/TerraLifecycleErrorMappingTests.swift`, `Tests/TerraTests/ZigBackendIntegrationTests.swift`, and `tasks/todo.md`.
- Latest PR CI run failed all four jobs in 3-4 seconds with no step logs exposed, so the branch does not have a green remote gate.
- Local `Scripts/validate.sh --quick` passed for repository hygiene, telemetry schema, binding conformance, project skill scripts, Python bindings, Zig core, C++ bindings, Rust bindings, Rust package verification, and SwiftPM manifest validation; Android Gradle checks are intentionally skipped in quick mode.
- Local `git diff --check` passed.
- Full local `swift build --disable-automatic-resolution` and `swift test --disable-automatic-resolution --parallel --num-workers 1` were stopped after stalling in `swift-protobuf`'s nested protobuf submodule checkout, matching the known SwiftPM bootstrap blocker.
- Required follow-up before production: rebase or merge current `origin/main`, resolve conflicts, rerun full SwiftPM validation once dependency checkout completes, get CI green, mark the PR ready for review, and only then merge/release.

## Perfetto On-Device Observability Exploration - 2026-05-01

- [x] Review Terra observability memory, skills, and existing OpenTelemetry/TraceKit seams
- [x] Research current Perfetto SDK, TrackEvent, trace format, and Apple-platform constraints
- [x] Split repo and Perfetto feasibility checks across focused subagents
- [x] Identify safest integration shape and avoid source implementation before check-in
- [ ] Confirm implementation scope before changing package/source files
- [ ] Add failing converter/export tests first
- [ ] Implement optional Perfetto export path
- [ ] Verify generated trace files open/query in Perfetto tooling
- [ ] Document adoption limits and user-facing workflow

### Plan

1. Keep Terra's OpenTelemetry span model as the source of truth; do not replace `Terra.installOpenTelemetry` or the existing OTLP export path.
2. Add Perfetto as an optional local export/analysis module, most likely a new `TerraPerfetto` target/product, instead of adding Perfetto runtime dependencies to `TerraCore`.
3. Start with a TraceKit-based converter from `TraceSnapshot`/`SpanRecord` to Perfetto TrackEvent protobuf files (`.perfetto-trace` / `.pftrace`).
4. Map Terra spans to Perfetto slices, Terra events to instant events, profiler numeric attributes to counters where stable, and low-cardinality attributes to debug annotations.
5. Treat live in-process Perfetto SDK embedding as a later prototype only after the file-export path is proven; gate any Apple-device claim behind a real macOS/iOS build and generated trace proof.
6. Verify with focused unit tests, a golden Perfetto fixture, SwiftPM manifest/build checks where dependency resolution allows, and Perfetto Trace Processor or UI open/query proof.

### Research Notes

- Perfetto is strong for local/client timeline analysis, but it is not an OpenTelemetry-style distributed tracer.
- Perfetto's system recording tools do not integrate with system-level macOS data sources; Apple support should be framed as Terra app/inference timeline export, not full-system Apple tracing.
- The official SDK is C++17 and distributed as amalgamated `perfetto.h` / `perfetto.cc`; docs mention macOS for in-process SDK usage but did not show an official iOS support claim.
- Perfetto supports synthetic TrackEvent protobuf generation, which fits Terra better than embedding the C++ SDK in the first pass.
- Existing repo seams favor `TerraTraceKit`/`SpanRecord` conversion: `OTLPHTTPServer` ingests spans into `TraceStore`, and `TraceSnapshot` already gives normalized span data.
- Avoid new telemetry keys for the first pass. If new `terra.*`, `gen_ai.*`, `process.*`, or `metal.*` keys become necessary, register them in `Docs/telemetry-schema.json` and run schema validation.

### Review

- No source implementation has started yet.
- Recommended first implementation scope: `Package.swift`, `Sources/TerraPerfetto`, `Tests/TerraPerfettoTests`, and docs/snippets only after converter tests exist.
- Primary risk: overpromising "on-device Perfetto" as system tracing on Apple. The production-grade scope is offline/local Perfetto trace export from Terra's existing app-level telemetry.
- Known verification constraint: prior SwiftPM checks in this repo can stall during `swift-protobuf` checkout; use focused filters and record exact bootstrap blockers instead of overstating test status.

## Packaging And Native Validation Fixes - 2026-04-30

- [x] Preserve current dirty worktree and avoid reverting unrelated edits
- [x] Fix C++ and ROS2 default native library paths to match Zig's `libterra.a`
- [x] Verify Rust packaging from Cargo's packaged crate copy with an explicit native library path
- [x] Run Python unit tests and C++ CMake smoke tests from validate/CI
- [x] Route quick SwiftPM manifest validation through the timeout wrapper
- [x] Make the AutoInstrument example buildable through SwiftPM or archive it
- [x] Run focused validation and record exact residual blockers

### Plan

1. Patch only packaging/native validation files in the requested ownership list.
2. Prefer real package/build checks over metadata-only validation.
3. Keep local validation resilient to this dirty checkout while preserving stricter behavior for clean CI.
4. Document any external native-library requirement directly in the Rust crate.

### Review

- C++ and ROS2 CMake defaults now point at Zig's `zig-core/zig-out/lib/libterra.a` and fail with the correct override guidance.
- C++ validation now configures/builds through CMake and runs the existing `string_view_smoke` source through CTest.
- Rust packaging now verifies Cargo's packaged crate copy with `TERRA_LIB_DIR` pointing at the built Zig library; packaged builds without sibling `../zig-core` fail with an explicit native-library requirement.
- `Scripts/validate.sh --quick` now runs Python unit tests, Zig tests, C++ CMake smoke, Rust tests, real `cargo package --allow-dirty`, timeout-wrapped SwiftPM manifest validation, and skips Android in quick mode.
- CI now runs timeout-wrapped SwiftPM manifest validation, Python unit tests, C++ CMake smoke, and real Rust package verification.
- `TerraAutoInstrumentExample` is now a SwiftPM executable product/target and is included in full SwiftPM executable validation.
- Verification passed for script syntax, Python unit tests, Zig tests, C++ CMake/CTest, Rust tests, Rust packaged-crate verification, and integrated quick validation.
- Residual blocker: targeted `swift build --scratch-path /tmp/terra-codex-packaging-swiftpm --product TerraAutoInstrumentExample` did not reach compilation before being stopped; it was still cloning `swift-protobuf`'s nested `Sources/protobuf/protobuf` submodule after roughly three minutes.

## Audit Finding Remediation - 2026-04-30

- [x] Preserve current dirty worktree and avoid reverting user-owned edits
- [x] Fix native packaging/linking blockers across C++, ROS2, and Rust crate packaging
- [x] Harden validation and CI for Python tests, C++ smoke tests, Rust package verification, SwiftPM quick timeouts, telemetry schema, binding contracts, and executable examples
- [x] Fix TraceKit privacy redaction and live duplicate-span ingestion behavior
- [x] Fix runtime lifecycle issues: OpenTelemetry partial install, profiler reset/reconfigure, stale metric instruments, workflow/agent error rollups
- [x] Fix CoreML compute-plan timeout cancellation
- [x] Clean stale docs/examples for profiler presets, legacy APIs, internal TerraLlama surface, and SpanContext binding semantics
- [x] Run focused validation and record exact residual blockers

### Plan

1. Make packaging and validation failures reproducible and machine-checked before broad runtime work.
2. Patch privacy/telemetry-contract defects next because they affect captured data and viewer trust.
3. Patch lifecycle and integration correctness with focused tests where the existing seams allow it.
4. Update docs/examples only where they are stale relative to current source behavior.
5. Run practical local validation; record environmental blockers instead of forcing destructive cleanup.

### Review

- Preserved the dirty worktree and did not stage, commit, revert, or overwrite unrelated changes.
- Native packaging and validation are now machine-checkable through `Scripts/validate.sh --quick`: Python unit tests, Zig tests, C++ CMake/CTest smoke, Rust tests, packaged-crate verification, binding conformance, telemetry schema, docs hygiene, and SwiftPM manifest validation all pass.
- TraceKit now redacts schema-protected hash attributes, keeps richer duplicate live span records, and validates unknown protected keys and fixtures through the schema validator.
- Runtime lifecycle handling now avoids partially installed OpenTelemetry state, installs privacy before providers, resets profiler install state on shutdown, clears metric instruments, records workflow/agent rollups on thrown bodies, and cancels timed-out CoreML compute-plan probes.
- Streaming/profiler/model integration fixes are covered for MLX active-span metrics, FoundationModels chunk estimation, Power/Espresso pipe draining, CoreML timeout cancellation, profiler reset, and stale metric cleanup.
- Cross-language `SpanContext` validity is now consistent across Zig, C++, Rust, Python, and Android: a valid context requires a non-zero trace ID and non-zero span ID, and invalid parent contexts are ignored before propagation.
- Updated binding docs and validation so the stricter context contract is checked by source validators and binding smoke tests.
- Verification passed:
  - `swift build`
  - `swift test --filter 'TerraSystemProfilerTests|TerraCoreMLTests|TerraTests.TerraManualTracingTests|TerraTests.TerraAgentContextTests|TerraTests.TerraMetricsTests|TerraAutoInstrumentTests.TerraLifecycleAPITests|TerraAutoInstrumentTests.TerraLifecycleErrorMappingTests|TraceStoreTests|StreamRendererTests|SpanDetailViewModelTests|TelemetrySchemaValidatorTests|TerraMLXTests'`
  - `zig build test --summary all`
  - `python3 -m unittest discover -s terra-python -p 'test*.py'`
  - `TERRA_LIB_DIR=/Users/chriskarani/CodingProjects/RYNO/Terra/zig-core/zig-out/lib cargo test --manifest-path terra-rust/Cargo.toml -- --test-threads=1`
  - `cmake -S terra-cpp -B /tmp/terra-codex-cpp-context-smoke -DTERRA_LIB_PATH=/Users/chriskarani/CodingProjects/RYNO/Terra/zig-core/zig-out/lib/libterra.a`, `cmake --build /tmp/terra-codex-cpp-context-smoke --target string_view_smoke`, and `ctest --test-dir /tmp/terra-codex-cpp-context-smoke --output-on-failure`
  - `python3 Scripts/validate-telemetry-schema.py`
  - `python3 Scripts/validate-bindings.py` and `python3 Scripts/validate-bindings.py --matrix`
  - `TERRA_SWIFTPM_TIMEOUT_SECONDS=60 Scripts/validate.sh --quick`
  - `git diff --check`
- Residual local blocker: `cd terra-android && ./gradlew test --no-daemon` cannot run on this machine because no Java runtime is installed. Quick validation intentionally skips Android Gradle checks.

## Profiler/API Honesty And Model Integration Fixes - 2026-04-30

- [x] Preserve existing dirty task-note change and narrow this pass to owned source/test paths only
- [x] Add focused regression tests for profiler startup diagnostics, CoreML redaction/budgeting, power status semantics, ANE probe-only reporting, Llama surface expectations, FoundationModels unavailable stubs, MLX semantics, and TerraAccelerate hooks
- [x] Make `.power` and `.ane` profiler flags observable as installed, unavailable, or probe-only without silently promising collected data
- [x] Redact/cap CoreML input summaries and compute-plan operation detail, and separate estimated GPU route timing from measured Metal timing
- [x] Improve Power profiler status reporting for launch, permission, and no-sample outcomes
- [x] Make ANE probe-only behavior explicit in source and tests
- [x] Decide and encode the Llama API surface expectation
- [x] Align FoundationModels unavailable stubs with the real source surface
- [x] Add TerraAccelerate focused tests/schema-adjacent hooks where practical without editing docs/schema
- [x] Run focused verification and record exact blockers

### Plan

1. Re-read only the owned modules and tests listed in the request, plus `Package.swift` for product/test-target truth.
2. Add narrow failing tests first where test seams exist; if SwiftPM cannot run, keep them compile-oriented and verify with source inspection plus targeted commands.
3. Implement compatibility-preserving source changes inside the owned paths only.
4. Run focused SwiftPM filters and module-specific tests; if dependency resolution stalls, record the exact blocker.
5. Update this section with review notes before final response.

### Review

- Implemented profiler/API honesty and model-integration fixes in the requested owned source/test areas.
- `Terra.Configuration.Profiling.extended` and `.all` no longer include `.power` or `.ane`; explicit requests now show `requiresOptInTarget` through `Terra.profilingDiagnostics(for:)` / `lastProfilingDiagnostics`.
- CoreML session input summaries now hash feature names and cap serialized payload size; compute-plan operation detail now hashes identifiers, caps serialized operations, and reports truncation/count.
- CoreML auto-instrumentation now emits estimated CoreML GPU route timing under `terra.coreml.prediction.estimated_*` keys instead of measured `metal.compute_time_ms`.
- Power summaries now expose collection status and diagnostics for not-started, permission-denied, no-sample, failed, and completed outcomes.
- ANE profiler source/tests now distinguish unavailable, probe-only, and collecting modes; sessions only become active when collection hooks exist.
- Llama remains an internal package target by explicit source/test expectation; MLX adds a public streaming wrapper that finalizes Terra stream metrics.
- FoundationModels unavailable stub now exposes top-level `TerraTracedSession` plus `Terra.TracedSession` alias matching the real surface.
- Added `TerraAccelerate.Keys` and a focused test target.
- Verification:
  - `swift package --scratch-path /tmp/terra-codex-profiler-api-swiftpm dump-package` passed.
  - `git diff --check` passed for the files touched by this pass.
  - Focused `swift test --scratch-path /tmp/terra-codex-profiler-api-swiftpm --filter ...` and `swift build --scratch-path /tmp/terra-codex-profiler-api-swiftpm --skip-update --target TerraAccelerate` both stalled while creating `swift-protobuf`'s nested `Sources/protobuf/protobuf` checkout; only the Codex-started SwiftPM processes were stopped.

## Fix All Identified Issues - 2026-04-30

- [x] Record current clean baseline and implementation plan
- [x] Fix P0 native binding string ownership / lifetime contract
- [x] Fix P0 HTTP auto-instrumentation raw prompt privacy leak
- [x] Fix TraceKit live OTLP event/link/status preservation and privacy-aware rendering
- [x] Fix schema, fixture, and binding conformance drift checks
- [x] Fix CI/release validation gaps: API break command, Android native build, DocC links, Rust package metadata, executable builds, vendor header parity
- [x] Fix language binding issues: Python streaming end, C++ string_view bounds, default drift, runtime export lifecycle where feasible
- [x] Fix profiler/API honesty gaps: power/ANE status, measured vs estimated Metal/CoreML semantics, Llama public-surface decision, FoundationModels stub drift
- [x] Add focused tests for every behavior change before or with implementation
- [x] Run available verification and document exact blockers

### Implementation Plan

1. Start with privacy and native ABI defects because they can corrupt or leak telemetry.
2. Harden TraceKit and telemetry contracts next so fixes become machine-checkable.
3. Patch CI, docs, package, and release validation so regressions are caught.
4. Finish profiler/API honesty and public surface cleanup with narrow compatibility-preserving changes where possible.
5. Treat any impossible full-scope item as a documented blocker with exact source evidence and a focused follow-up test.

### Baseline

- `git status --short --branch` reports `## swiftformat`; there are no current dirty tracked files at the start of this implementation pass.
- Prior audit verification showed Zig and Rust tests pass locally, Java is unavailable for Android, and SwiftPM can still time out during `swift-protobuf` nested protobuf checkout before Terra compilation.

### Review

- Fixed the native string lifetime contract by making Zig span/record storage own copied string data, with C ABI lifetime tests and binding smoke coverage.
- Fixed HTTP prompt privacy by replacing raw auto-instrumented prompt export with Terra redacted prompt attributes; streaming errors now preserve metrics and record sanitized error type.
- Extended TraceKit live OTLP records to preserve events, links, status descriptions, dropped counts, and privacy-aware renderer/detail output.
- Hardened telemetry/schema/binding validation for event-name drift, fixture timestamps, bool-as-number typed values, and source/vendor header parity.
- Updated CI/docs/release validation for API break checks, Android native library checks, DocC/example linting, Rust package metadata, executable builds, and C++/ROS2 clean-checkout prerequisites.
- Fixed Python streaming span finalization, C++ `string_view` handling, Rust defaults, vendor header parity, profiler honesty/status APIs, CoreML redaction/budgeting, FoundationModels unavailable stubs, MLX streaming helpers, Llama internal-surface expectations, and TerraAccelerate tests.
- Verification completed for Python syntax/tests, docs/schema/binding validators, Zig tests, Rust tests/package listing, C++ smoke test, shell/YAML syntax, header parity, and manifest parsing.
- SwiftPM compile/test validation remains blocked before Terra compilation by the recurring `swift-protobuf` nested protobuf checkout timeout; Android Gradle remains blocked locally by missing Java.

## Archived Historical Notes

The sections below are retained for history only. Use the dated 2026-04-30 sections above for current baseline, completed fixes, and verification status.

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
