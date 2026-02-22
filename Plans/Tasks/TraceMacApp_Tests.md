Prompt:
Write Swift Testing tests (test-first) for TraceViewModel behavior, TraceStore integration (if test hooks exist), and renderer adapter mapping logic.

Goal:
Define expected behavior and guard against regressions with deterministic tests.

Task Breakdown:
- Add a Swift Testing target for TraceMacApp or an appropriate test module.
- Write failing tests for TraceViewModel snapshot refresh and selection behavior.
- If possible, add integration tests using sample OTLP payloads for TraceStore.
- Write tests validating renderer mapping logic (no pixel tests).
- Ensure tests are deterministic and do not require UI.

Expected Output:
- New test files under Tests/ that currently fail until implementation exists.
- Clear test coverage of view model and renderer adapter logic.
