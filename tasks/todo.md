# Terra Agentic DX Plan

- [x] Add explicit parent binding and detached propagation helpers to Terra tracing
- [x] Add `Terra.agentic` and `AgentHandle` as the canonical agent-loop API
- [x] Redesign `TerraError` for agentic guidance and migrate lifecycle/manual tracing call sites
- [x] Update discovery/examples/docs/macros to prefer the agentic and string-first surfaces
- [x] Add or update focused tests for parent linkage, detached propagation, discovery, and error guidance
- [ ] Run targeted and full-package verification

## Review

- Added explicit parent binding through Terra's fluent and composable call surfaces so agent, inference, tool, safety, and embedding spans can be attached to a chosen `SpanHandle`.
- Added `Terra.agentic`, `AgentHandle`, and detached-task helpers that rebind trace context for agentic workflows instead of relying on ambient task-local state.
- Extended `TerraError` with agentic guidance and detached-context remediation without breaking the existing compatibility surface.
- Updated discovery surfaces and examples to make `Terra.agentic` the preferred pattern for iterative tool-using workflows.
- Added focused tests covering explicit parent override, agent root-child relationships, and detached propagation helpers.
- Focused verification passed for composable API, manual tracing, agent context, error remediation, and the isolated `ProfilerInstallState` suite.
- `swift test` still exits with Swift Testing runner signal 11 after the XCTest bundle passes; the crash reproduces in unrelated profiler/error-remediation coverage and is not isolated to the new agentic changes.
