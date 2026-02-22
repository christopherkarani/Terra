# Task: Trace CLI — Tests (Timestamp Formatting + Concurrency)

Prompt:
Create failing tests that lock down renderer timestamp formatting and renderer/store concurrency behavior per the immutable plan.

Goal:
Define deterministic, reproducible tests that validate timestamp formatting and concurrency safety for renderer output.

Task Breakdown:
- Locate existing Trace CLI test targets and add new tests in the most appropriate module.
- Add tests that verify:
  - Timestamp formatting is stable and deterministic across locales/time zones.
  - Renderer output uses the expected timestamp format for both stream and tree modes.
  - Concurrency behavior is safe: no shared mutable formatter or data races in concurrent rendering paths.
- Use fixed timestamps/fixtures; avoid wall-clock time and randomness.
- Do not modify production code in this task.

Expected Output:
- New failing tests under `Tests/` covering renderer timestamp formatting and concurrency.
- Short note identifying which tests currently fail and the expected reasons.
