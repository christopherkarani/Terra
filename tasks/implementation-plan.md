# Terra 79→90 Implementation Plan

**Date:** 2026-02-25  
**Objective:** Raise codebase quality from strict 79/100 to 90+/100 with measurable hardening in privacy, reliability, concurrency safety, CI rigor, and operational readiness.

## 1) Success Criteria (Definition of Done)

- [ ] No privacy-sensitive path lacks automated regression tests.
- [ ] No flaky test behavior across two consecutive full `swift test` runs.
- [ ] All public API break checks fail PRs when violations are detected.
- [ ] Trace ingestion limits and timeout behavior are covered with adversarial tests.
- [ ] Public docs match current runtime behavior and defaults.
- [ ] Open high/medium audit findings are closed or explicitly accepted with owner + rationale.

## 2) Scope

### In Scope

- `Sources/Terra/` (privacy defaults, error recording, concurrency boundaries)
- `Sources/TerraHTTPInstrument/` (attribute surface + request instrumentation safety)
- `Sources/TerraAutoInstrument/` (default behavior and host coverage)
- `Sources/TerraTraceKit/` (ingestion robustness, decode limits, file safety)
- `.github/workflows/ci.yml` (quality gates + deterministic toolchain behavior)
- `Tests/` (regression + robustness test expansion)
- `README.md`, `CLAUDE.md` (behavioral and operational documentation accuracy)

### Out of Scope

- New product features unrelated to audit findings
- Broad refactors without quality/safety impact
- Dependency ecosystem cleanup beyond critical CI/security impact

## 3) Workstreams and Timeline (1 Week)

### Day 1 — Concurrency Hardening

- [ ] Inventory `@unchecked Sendable` usage and classify by risk.
- [ ] Replace or contain unsafe cross-thread access where practical (actors/locks/single-writer ownership).
- [ ] Add focused tests for concurrent span operations and lifecycle transitions.
- **Deliverable:** reduced unchecked-safety surface with explicit invariants in code.

### Day 2 — Privacy Contract Enforcement

- [ ] Verify privacy defaults across all span entry points (`withInferenceSpan`, tools, safety, agent).
- [ ] Ensure forbidden fields (raw prompt, disallowed `exception.message`) never leak when policy denies capture.
- [ ] Add negative tests for every protected attribute family.
- **Deliverable:** enforced privacy contract backed by tests.

### Day 3 — TraceKit Adversarial Robustness

- [ ] Expand tests for malformed payloads, deep nesting, oversized attribute maps, truncated/partial requests.
- [ ] Verify connection-close behavior cancels in-flight decode/ingest work.
- [ ] Validate deterministic timeout and rejection semantics.
- **Deliverable:** hardened ingestion behavior under hostile/invalid input.

### Day 4 — CI Gate Tightening

- [ ] Ensure API-break checks are required for all public products.
- [ ] Keep linter/tool versions pinned and reproducible.
- [ ] Split fast/slow test execution where needed for reliability and signal quality.
- **Deliverable:** CI blocks unsafe merges and provides deterministic outcomes.

### Day 5 — Dependency and Warning Hygiene

- [ ] Triage build/test warnings into actionable vs accepted third-party noise.
- [ ] Document accepted external warnings with owner and revisit date.
- [ ] Remove repo-owned warning sources that obscure real regressions.
- **Deliverable:** cleaner signal-to-noise in local and CI output.

### Day 6 — Docs and Runbooks

- [ ] Align `README.md` with exact privacy + instrumentation defaults.
- [ ] Align `CLAUDE.md` architecture map with real module/file layout.
- [ ] Add a short incident runbook for OTLP ingest failures/timeouts.
- **Deliverable:** no known doc/runtime drift for audited areas.

### Day 7 — Release Readiness Review

- [ ] Run full verification pass (tests + targeted resilience/privacy suites).
- [ ] Summarize residual risks and explicit follow-ups.
- [ ] Prepare release-quality change summary for maintainers.
- **Deliverable:** final readiness report with pass/fail status against success criteria.

## 4) Verification Plan

- **Core test command:** `swift test`
- **Targeted gates:**
  - `swift test --filter TerraRedactionPolicyTests`
  - `swift test --filter TerraInferenceSpanTests`
  - `swift test --filter OTLPRequestDecoderTests`
  - `swift test --filter OTLPHTTPServerTests`
- **Flake check:** run full `swift test` twice before completion sign-off.

## 5) Risks and Mitigations

- **Risk:** Concurrency hardening introduces behavior change.
  - **Mitigation:** isolate changes behind existing API behavior + add regression tests first.
- **Risk:** CI strictness increases short-term PR friction.
  - **Mitigation:** phase in with clear failure messages and fast feedback jobs.
- **Risk:** Third-party warnings mask real regressions.
  - **Mitigation:** document accepted baseline and fail only on new repo-owned warnings.

## 6) Ownership and Tracking

- **Tracking file:** `tasks/todo.md`
- **Evidence artifacts:** test output snippets, changed file list, and final review notes.
- **Completion rule:** every checklist item above is either checked or deferred with owner + date.
