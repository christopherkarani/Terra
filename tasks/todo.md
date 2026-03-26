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
