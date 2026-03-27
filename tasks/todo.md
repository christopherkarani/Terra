# Release 0.2.4

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
