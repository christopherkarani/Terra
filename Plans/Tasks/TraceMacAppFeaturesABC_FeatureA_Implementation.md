Prompt:
Implement Feature A (timeline bar selection with highlight and detail sync) to satisfy tests.
Goal:
Introduce a single selection source of truth and wire timeline bar, highlight, and detail view to the same selection state.
Task Breakdown:
- Add or extend the selection model to represent none vs span id.
- Wire timeline bar selection updates into the view model.
- Bind highlight state and detail view to selection state.
- Keep public API minimal and explicit; enforce Sendable if needed.
Expected Output:
- Updated view model(s) and views implementing Feature A.
- Tests from Feature A pass.
