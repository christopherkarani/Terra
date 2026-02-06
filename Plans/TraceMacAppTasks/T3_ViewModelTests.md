Prompt:
Create Swift Testing tests for TraceViewModel behavior: list/filter/search, timeline mapping, and span detail selection as defined by the TraceMacApp plan.

Goal:
Define view model behavior and state transitions so UI wiring can be implemented confidently without UI tests.

Task Breakdown:
1. Add a new Swift Testing file for view model tests.
2. Write tests for trace list view model: sorting by date, search/filter by trace name/id, and selection state.
3. Write tests for timeline view model: spans mapped into rows/lanes, ordering by start time, and highlighting errors/critical spans.
4. Write tests for detail view model: selected span attributes/events/links surfaced, and clearing selection resets detail state.
5. Use in-memory model fixtures; no filesystem I/O.

Expected Output:
- New Swift Testing test file(s) under `Tests/` for view model behavior.
- Tests fail because view model implementation does not yet exist.
