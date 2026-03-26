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
