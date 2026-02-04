# Production Readiness Plan (Immutable)

**Project:** Terra  
**Owner:** CTO / Orchestrator  
**Date:** 2026-02-04

## Goals
- Add Apache-2.0 licensing to make distribution and contributions legally clear.
- Establish CI to gate merges with tests.
- Implement integration tests using Swift Testing that validate critical behavior end-to-end.
- Resolve concurrency risk in `Terra.Scope` around `@unchecked Sendable`.
- Fix the `installOpenTelemetry` race condition.
- Clarify and validate persistence path expectations across platforms.
- Introduce versioning for instrumentation (`instrumentationVersion`).
- Update README/docs to reflect production usage, CI, licensing, and instrumentation versioning.

## Constraints
- Correctness is the top priority, followed by Swift type safety, API clarity, then performance.
- Strict TDD with Swift Testing for all new behavior and fixes.
- Public APIs require doc comments and must be hard to misuse.
- Concurrency must be structured and `Sendable`-safe.
- Plan is immutable once approved.
- No implementation work before tests exist for each behavior.

## Non-Goals
- Feature expansion unrelated to production readiness.
- Large refactors not required for the listed findings.
- Performance optimization unless required to eliminate correctness risk.
- New platform support beyond what Terra already targets.

## Architecture Decisions
- Concurrency safety will be enforced at the boundary: `Terra.Scope` will be made explicitly `Sendable` only if proven safe by design or through value semantics; otherwise it must encapsulate non-Sendable state and expose safe APIs.
- `installOpenTelemetry` will be made idempotent and race-free with a single source of truth for initialization state.
- Integration tests will target end-to-end flows around instrumentation and persistence, using Swift Testing and deterministic fixtures.
- Instrumentation versioning will be centralized and exposed via a single API surface, with documentation indicating its stability and usage.
- Persistence path expectations will be documented and validated via tests that assert actual resolved paths per platform.

## Task List and Agent Mapping

1. **Context Gathering**
   - Agent: Context / Research Agent
   - Goal: Inspect codebase areas relevant to licensing, CI, tests, `Terra.Scope`, `installOpenTelemetry`, persistence paths, and documentation.
   - Expected Output: Summary of current state and risks without code changes.

2. **Plan Validation**
   - Agent: Planning Agent
   - Goal: Validate this plan against codebase realities and confirm no missing critical production concerns.
   - Expected Output: Approval or a minimal amendment list that does not change plan scope.

3. **Task Decomposition**
   - Agent: Planning Agent
   - Goal: Split this plan into task files in `Plans/Tasks/` with the required format.
   - Expected Output: One task file per major workstream.

4. **Test-First Execution**
   - Agent: Implementation Agent
   - Goal: Add failing Swift Testing integration tests covering:
     - Instrumentation initialization.
     - Persistence path resolution.
     - Idempotent OpenTelemetry setup.
     - Concurrency boundaries where applicable.
   - Expected Output: Failing tests, no production code changes yet.

5. **Fix Concurrency Risk in `Terra.Scope @unchecked Sendable`**
   - Agent: Implementation Agent
   - Goal: Remove `@unchecked Sendable` or demonstrate safety via structural changes.
   - Expected Output: Updated implementation and passing tests; no new public API ambiguity.

6. **Fix `installOpenTelemetry` Race**
   - Agent: Implementation Agent
   - Goal: Make initialization thread-safe and idempotent.
   - Expected Output: Passing tests and deterministic behavior under concurrent calls.

7. **Persistence Path Expectations**
   - Agent: Implementation Agent
   - Goal: Document expected paths and enforce via tests; adjust code if paths are inconsistent.
   - Expected Output: Updated docs and tests; code fixes if required.

8. **Add `instrumentationVersion`**
   - Agent: Implementation Agent
   - Goal: Provide explicit instrumentation versioning API and document it.
   - Expected Output: API addition, doc comments, tests verifying version usage.

9. **Add Apache-2.0 License**
   - Agent: Implementation Agent
   - Goal: Add `LICENSE` file and include notice in README.
   - Expected Output: License file and README update.

10. **Add CI**
    - Agent: Implementation Agent
    - Goal: Add CI config that runs Swift Testing and `swift test` on PRs.
    - Expected Output: CI configuration and README status badge if applicable.

11. **Documentation Updates**
    - Agent: Implementation Agent
    - Goal: Update README and docs for installation, usage, instrumentation versioning, persistence paths, and CI.
    - Expected Output: Doc updates consistent with new behavior.

12. **Code Review**
    - Agent: Code Review Agent(s)
    - Goal: Review changes for plan compliance, concurrency safety, API clarity, and test coverage.
    - Expected Output: Review notes and approval or identified gaps.

13. **Gap Resolution**
    - Agent: Fix / Gap Agent
    - Goal: Address any review gaps and re-run relevant tests.
    - Expected Output: Fully passing tests and closed gaps.

14. **Final System Review**
    - Agent: Code Review Agent
    - Goal: Holistic validation of architecture, tests, docs, and production readiness.
    - Expected Output: Final approval statement.

## Deliverables
- `LICENSE` (Apache-2.0)
- CI configuration
- Swift Testing integration tests
- Concurrency-safe `Terra.Scope`
- Race-free `installOpenTelemetry`
- Documented and validated persistence paths
- `instrumentationVersion` API
- Updated README/docs

## Acceptance Criteria
- All tests pass in CI and locally.
- No `@unchecked Sendable` usage without justified safety proof.
- OpenTelemetry setup is deterministic under concurrency.
- Documentation matches actual runtime behavior.
- Instrumentation versioning is discoverable and stable.
- Licensing is compliant and present.
