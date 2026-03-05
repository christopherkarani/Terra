# Terra v3 RC Qualification Checklist (Phase 9)

Date: 2026-03-03  
Branch: `api-design`  
Evidence logs: `/tmp/terra-rc-phase9-20260304-013833`

## Release Gates

- [x] `swift test` passes.
- [x] Required filtered suites pass.
- [x] Strict concurrency check reports `STRICT_ERRORS=0`.
- [x] Deprecation sweep completed and reviewed.
- [x] Internal consistency grep checks completed and reviewed.
- [x] No known P1/P2 issues remain from qualification.
- [x] RC artifacts updated (`Docs/RC_CHECKLIST.md`, `tasks/todo.md`).

## Root Cause + Fix (Full-Suite Failure)

- Root cause 1: test isolation used a thread-affine `NSRecursiveLock`, but async tests can lock/unlock across different threads.
- Root cause 2: several XCTest classes held `TerraTestSupport` for the entire test class lifetime and only released lock ownership in `deinit`, causing order-dependent lock contention in full-suite runs.
- Fix:
  - Switched testing isolation lock to `DispatchSemaphore(value: 1)` in `Terra+OpenTelemetry`.
  - Added async thread-hop regression coverage in `HTTPIntegrationTests`.
  - Updated affected XCTest classes to `support = nil` in `tearDown()` after reset so lock ownership is released per test method.

## TDD Evidence

- Reproduced failing/full-suite hang behavior (`swift test`).
- Added deterministic regression test: `testTestingIsolationLockSupportsAsyncThreadHop`.
- Implemented minimal lock + teardown lifecycle fix.
- Re-ran focused and full suites until green.

## Command Evidence

| # | Command | Exit | Result | Evidence |
|---|---|---:|---|---|
| 1 | `swift test` | 0 | PASS | `Test run with 167 tests passed` |
| 2 | `swift test --filter TerraTests` | 0 | PASS | `Test run with 36 tests passed` |
| 3 | `swift test --filter TerraAutoInstrumentTests` | 0 | PASS | `Test run with 37 tests passed` |
| 4 | `swift test --filter TerraTracedMacroTests` | 0 | PASS | `Test run with 24 tests passed` |
| 5 | `swift test --filter TerraMLXTests` | 0 | PASS | `Test run with 12 tests passed` |
| 6 | `swift test --filter TerraTraceKitTests` | 0 | PASS | `Test run with 21 tests passed` |
| 7 | `swift test --filter TerraHTTPInstrumentTests` | 0 | PASS | `Test run with 20 tests passed` |
| 8 | `STRICT_ERRORS=$(swift build -Xswiftc -strict-concurrency=complete 2>&1 \| grep -c "error:"); echo "STRICT_ERRORS=$STRICT_ERRORS"` | 0 | PASS | `STRICT_ERRORS=0` |
| 9 | `rg "@available.*deprecated" Sources/` | 0 | PASS | Deprecated annotations confirmed in expected compatibility surfaces (`Terra+FluentAPI`, `Terra+KeyV3`). |
| 10 | `rg "\.run\s*\{" Sources/ --count` | 1 | PASS | No internal `.run {` usage found (expected zero-match). |
| 11 | `rg "sha256Hex" Sources/ --count` | 0 | PASS | `Sources/Terra/Terra.swift:2`, `Sources/Terra/Terra+Runtime.swift:4` |
| 12 | `rg "withInferenceSpan\|withStreamingInferenceSpan\|withAgentInvocationSpan" Examples/` | 1 | PASS | No legacy span-wrapper helpers in examples (expected zero-match). |
| 13 | `rg "Terra\.enable\|Terra\.configure\|Terra\.install\|Terra\.bootstrap" Examples/` | 1 | PASS | No legacy setup APIs in examples (expected zero-match). |

## Notes

- `rg` returns exit code `1` for no matches; for checks #10, #12, and #13 that is the expected passing condition.
- Command #8 was executed as the exact one-liner above and returned `STRICT_ERRORS=0`.
