Prompt:
Implement TraceViewModel layer per plan and T3 tests: list/filter/search, timeline mapping, and span detail view models.

Goal:
Provide Swifty, type-safe view models that translate model data into UI-ready state without AppKit dependencies.

Task Breakdown:
1. Implement list view model with sorted traces, search/filter logic, and selection state.
2. Implement timeline view model that maps spans into lanes/rows with ordering, highlighting errors/critical spans and long durations.
3. Implement detail view model that exposes selected span attributes, events, and links with stable formatting.
4. Wire view model updates with simple callbacks/notifications as per plan (no extra dependencies).
5. Ensure all T3 tests pass without changing test expectations.

Expected Output:
- New or updated source files under `Sources/` implementing TraceViewModel.
- All T3 tests pass.
