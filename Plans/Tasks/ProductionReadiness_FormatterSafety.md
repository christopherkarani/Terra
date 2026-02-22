# Task: TerraTraceKit — Formatter Safety (Timestamp Formatting)

Prompt:
Remove shared `ISO8601DateFormatter` usage in TerraTraceKit to ensure thread-safe, deterministic timestamp formatting.

Goal:
Eliminate shared mutable formatter state and make renderer timestamp formatting safe under concurrency.

Task Breakdown:
- Locate all `ISO8601DateFormatter` usage in TerraTraceKit renderers/utilities.
- Replace any shared/static formatter with a safe alternative:
  - Per-use formatter creation, or
  - A concurrency-safe wrapper (e.g., actor/local cache), as appropriate.
- Ensure the formatting remains consistent with existing output expectations and tests.
- Avoid unrelated formatting or linting tool changes.

Expected Output:
- TerraTraceKit updated to remove shared formatter state.
- Renderer timestamp formatting remains stable and deterministic.
- Notes describing the chosen safe approach.
