# Terra v3 RC Qualification Checklist (Phase 9)

Date: 2026-03-03  
Branch: `api-design`  
Evidence logs: `/tmp/terra-matrix-20260303-171823`

## Release Gates

- [x] `swift test` passes.
- [x] Required filtered suites pass.
- [x] Strict concurrency check reports `STRICT_ERRORS=0`.
- [x] Deprecation sweep completed and reviewed.
- [x] Internal consistency grep checks completed and reviewed.
- [x] No known P1/P2 issues remain from qualification.
- [x] RC artifacts updated (`Docs/RC_CHECKLIST.md`, `tasks/todo.md`).

## Root Cause + Fix (Full-Suite Failure)

- Root cause: order-dependent global state leakage in test targets that installed custom Terra/OpenTelemetry providers without shared isolation/reset protocol.
- Affected tests: `TerraMLXTests`, `TerraTracedMacroTests`, `TerraHTTPInstrumentTests`.
- Fix: enforce deterministic test isolation (`lockTestingIsolation` + `resetOpenTelemetryForTesting` + provider restore/unlock teardown), and harden `TerraFoundationModels` span harness reset behavior.

## Command Evidence

| # | Command | Exit | Result | Evidence |
|---|---|---:|---|---|
| 1 | `swift test` | 0 | PASS | `Executed 68 tests, with 0 failures`; `Test run with 173 tests passed` |
| 2 | `swift test --filter TerraTests` | 0 | PASS | `Executed 52 tests, with 0 failures`; `Test run with 36 tests passed` |
| 3 | `swift test --filter TerraAutoInstrumentTests` | 0 | PASS | `Executed 0 tests, with 0 failures` (XCTest selection), `Test run with 43 tests passed` |
| 4 | `swift test --filter TerraTracedMacroTests` | 0 | PASS | `Executed 0 tests, with 0 failures` (XCTest selection), `Test run with 24 tests passed` |
| 5 | `swift test --filter TerraMLXTests` | 0 | PASS | `Executed 0 tests, with 0 failures` (XCTest selection), `Test run with 12 tests passed` |
| 6 | `swift test --filter TerraTraceKitTests` | 0 | PASS | `Executed 15 tests, with 0 failures`; `Test run with 21 tests passed` |
| 7 | `swift test --filter TerraHTTPInstrumentTests` | 0 | PASS | `Executed 1 test, with 0 failures`; `Test run with 20 tests passed` |
| 8 | `STRICT_ERRORS=$(swift build -Xswiftc -strict-concurrency=complete 2>&1 \| grep -c "error:"); echo "STRICT_ERRORS=$STRICT_ERRORS"` | 0 | PASS | `STRICT_ERRORS=0` |
| 9 | `rg "@available.*deprecated" Sources/` | 0 | PASS | 32 deprecated annotations found in expected compatibility surfaces (`Terra+FluentAPI`, `Terra+KeyV3`, `Terra+Start`) |
| 10 | `rg "\.run\s*\{" Sources/ --count` | 1 | PASS | no matches (`0` total), expected for v3 internal consistency |
| 11 | `rg "sha256Hex" Sources/ --count` | 0 | PASS | 2 matches (`Sources/Terra/Terra+Runtime.swift:4`, `Sources/Terra/Terra.swift:2`) |
| 12 | `rg "withInferenceSpan\|withStreamingInferenceSpan\|withAgentInvocationSpan" Examples/` | 1 | PASS | no matches (`0` total), expected after closure-first/API migration |
| 13 | `rg "Terra\.enable\|Terra\.configure\|Terra\.install\|Terra\.bootstrap" Examples/` | 1 | PASS | no matches (`0` total), examples avoid deprecated bootstrap/install surface |

## Notes

- `rg` exits `1` for zero matches. For checks #10, #12, and #13 that is expected and treated as PASS because the required state is absence.
- Third-party plugin warnings (dependency deprecations under `.build/checkouts`) were observed during builds/tests and are outside Terra-owned source.
