Prompt:
Add failing Swift Testing integration tests that cover instrumentation initialization, persistence path resolution, idempotent OpenTelemetry setup, and concurrency boundaries where applicable.

Goal:
Define the expected end-to-end behavior in tests before any production code changes, ensuring correctness and determinism.

Task Breakdown:
- Survey existing test structure under `Tests/` and Swift Testing usage.
- Write integration tests (Swift Testing) for:
- Instrumentation initialization end-to-end behavior.
- Persistence path resolution and platform expectations.
- Idempotent OpenTelemetry setup under repeated calls.
- Concurrency boundary expectations around `Terra.Scope` where applicable.
- Ensure tests are failing against current behavior (no production code changes yet).
- Keep tests deterministic with fixtures or controlled environment inputs.

Expected Output:
- New Swift Testing test files under `Tests/` with failing tests for the above behaviors.
