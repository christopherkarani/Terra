Prompt:
Fix core production issues: `Terra.Scope` concurrency safety, `installOpenTelemetry` race condition, persistence path correctness, and `instrumentationVersion` API.

Goal:
Eliminate concurrency risks and race conditions, enforce correct persistence behavior, and introduce explicit instrumentation versioning with clear, safe APIs.

Task Breakdown:
- Remove or justify `@unchecked Sendable` in `Terra.Scope` by making it structurally safe or encapsulating non-Sendable state with safe APIs.
- Make `installOpenTelemetry` idempotent and thread-safe with a single source of truth for initialization state.
- Validate and, if needed, fix persistence path resolution to match documented expectations across platforms.
- Add `instrumentationVersion` API (centralized, discoverable, with doc comments).
- Make all changes test-driven using the failing tests from the tests workstream.

Expected Output:
- Updated implementation with passing tests.
- No `@unchecked Sendable` without demonstrated safety.
- Deterministic, race-free OpenTelemetry initialization.
- Correct and validated persistence paths.
- Public `instrumentationVersion` API with doc comments.
