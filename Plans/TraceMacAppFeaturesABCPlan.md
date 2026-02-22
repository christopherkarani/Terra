# TraceMacApp Features A/B/C Plan

## Goals
- Implement A: timeline bar selection with highlight and detail sync.
- Implement B: span list with keyboard navigation.
- Implement C: search/filter wiring via toolbar.
- Use strict TDD with Swift Testing for all behavior.
- Preserve correctness and Swift type safety above all else.

## Constraints
- Swift 6.2, macOS app.
- No UI tests in this scope.
- Swift Testing framework required. XCTest only if Swift Testing is impossible.
- Plan is immutable after creation.
- Keep public API surface minimal and explicit.
- Enforce Sendable where concurrency appears.

## Non-Goals
- Visual redesign or theming changes.
- Performance optimizations without measured need.
- Broad refactors unrelated to A/B/C.
- UI tests or snapshot tests.

## Architecture Decisions
- Introduce a single selection source of truth in view model state.
- Model selection as a value type that can represent “none” and “span id”.
- Timeline bar and detail view are bound to the same selection state.
- Span list keyboard navigation uses commands and focus state rather than custom event taps.
- Search/filter toolbar binds to a typed filter model in view model, not raw strings in views.
- Use protocol abstractions only when needed to test or isolate state logic.

## TDD Strategy
- Create failing Swift Testing tests for each feature before implementation.
- Tests focus on state transitions and view model behavior, not UI rendering.
- Each feature gets a focused test file with behavior-driven names.

## Detailed Todo
1. Codebase discovery
1. Identify current selection, timeline bar, span list, and toolbar wiring.
1. Enumerate existing view models and selection or filter types.

1. Feature A tests
1. Add tests for selection changes from timeline bar input.
1. Add tests for highlight state derived from selection.
1. Add tests for detail view syncing on selection change.

1. Feature A implementation
1. Add or extend selection model.
1. Wire timeline bar selection to view model.
1. Bind highlight state and detail view to selection.

1. Feature B tests
1. Add tests for keyboard navigation in span list.
1. Add tests for moving selection up/down within bounds.
1. Add tests for selection update triggering detail sync.

1. Feature B implementation
1. Add keyboard command handlers or focus-based actions.
1. Update view model selection based on keyboard navigation.

1. Feature C tests
1. Add tests for toolbar inputs updating filter state.
1. Add tests for filter state affecting span list results.

1. Feature C implementation
1. Bind toolbar controls to filter model.
1. Apply filter to span list data pipeline.

1. Integration verification
1. Ensure selection stays consistent across A and B.
1. Ensure filter changes do not break selection invariants.
1. Run full Swift Testing suite.

## Task to Agent Mapping
- Context/Research Agent: codebase discovery and current state mapping.
- Planning Agent: produce this plan.
- Implementation Agent: implement A/B/C following tests.
- Code Review Agent: review each feature as it lands.
- Fix/Gap Agent: address review gaps and regressions.

## Deliverables
- Updated view models with selection and filter state.
- New Swift Testing test suites for A/B/C.
- Updated views and bindings for timeline bar, span list, toolbar.
