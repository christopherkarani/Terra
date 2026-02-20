# Terra v1 RC Hardening Report

## RC Metadata
- Commit SHA: `f2f7822ace91af6d1364f88bf6f767e86e7ae0be`
- Contract: `terra.v1`
- Generated (UTC): `2026-02-20T22:06:13Z`
- Scope: Live runtime validation, perf gates, stress determinism, parser invariants, UI telemetry parity, fixture hygiene, and CI gate wiring.

## Gate Commands
```bash
TERRA_ENABLE_LIVE_PROVIDER_TESTS=1 swift test --filter LiveProviderIntegrationTests
TERRA_ENABLE_PERF_GATES=1 swift test --filter TerraPerformanceGateTests
TERRA_ENABLE_PERF_GATES=1 swift test --filter HTTPPerformanceGateTests
TERRA_ENABLE_PERF_GATES=1 swift test --filter TraceMacAppPerformanceGateTests
swift test --filter TerraCompliancePolicyTests.testConcurrentPolicySuppression_isDeterministicAcrossRepeatedRounds
swift test --filter OTLPHTTPServerTests.testOTLPHTTPServerMixedConcurrentAllowRejectStressIsDeterministic
swift test --filter 'AIResponseStreamParserTests|HTTPIntegrationTests'
swift test --filter TerraV1FixtureTests
./Scripts/rc_hardening.sh
```

## Artifact Paths
- JSON summary: `/Users/chriskarani/CodingProjects/Terra/Artifacts/rc-hardening/latest/rc-hardening-summary.json`
- Text summary: `/Users/chriskarani/CodingProjects/Terra/Artifacts/rc-hardening/latest/rc-hardening-summary.txt`
- Terra perf gate: `/Users/chriskarani/CodingProjects/Terra/Artifacts/rc-hardening/latest/terra-performance-gate.json`
- HTTP perf gate: `/Users/chriskarani/CodingProjects/Terra/Artifacts/rc-hardening/latest/http-performance-gate.json`
- TraceMacApp perf gate: `/Users/chriskarani/CodingProjects/Terra/Artifacts/rc-hardening/latest/tracemacapp-performance-gate.json`

## Latest RC Gate Run
- Command: `./Scripts/rc_hardening.sh`
- Result: `Overall: pass`
- Summary artifact: `/Users/chriskarani/CodingProjects/Terra/Artifacts/rc-hardening/latest/rc-hardening-summary.json`

## Step Outcomes
- `live-provider-matrix`: status=`skipped`, required=`required`, duration=`0s`
  - note: Live provider matrix disabled (set TERRA_ENABLE_LIVE_PROVIDER_TESTS=1 to execute).
  - log: `/Users/chriskarani/CodingProjects/Terra/Artifacts/rc-hardening/latest/live-provider-matrix.log`
- `perf-terra`: status=`pass`, required=`required`, duration=`33s`
  - note: Runs Terra inference/streaming overhead gates (p50<=3%, p95<=7%).
  - log: `/Users/chriskarani/CodingProjects/Terra/Artifacts/rc-hardening/latest/perf-terra.log`
- `perf-http`: status=`pass`, required=`required`, duration=`140s`
  - note: Runs HTTP stream parser overhead gate (p50<=3%, p95<=7%).
  - log: `/Users/chriskarani/CodingProjects/Terra/Artifacts/rc-hardening/latest/perf-http.log`
- `perf-tracemacapp`: status=`pass`, required=`required`, duration=`125s`
  - note: Runs TraceMacApp timeline compaction/render-prep overhead gate (p50<=3%, p95<=7%).
  - log: `/Users/chriskarani/CodingProjects/Terra/Artifacts/rc-hardening/latest/perf-tracemacapp.log`
- `compliance-stress`: status=`pass`, required=`required`, duration=`37s`
  - note: Runs concurrent compliance suppression determinism stress.
  - log: `/Users/chriskarani/CodingProjects/Terra/Artifacts/rc-hardening/latest/compliance-stress.log`
- `otlp-reject-stress`: status=`pass`, required=`required`, duration=`1s`
  - note: Runs mixed allow/reject/schema OTLP stress and verifies deterministic 200/403/400 outcomes.
  - log: `/Users/chriskarani/CodingProjects/Terra/Artifacts/rc-hardening/latest/otlp-reject-stress.log`
- `stream-invariants`: status=`pass`, required=`required`, duration=`1s`
  - note: Runs parser + HTTP integration invariants for out-of-order timestamps and recovery.
  - log: `/Users/chriskarani/CodingProjects/Terra/Artifacts/rc-hardening/latest/stream-invariants.log`
- `fixture-hygiene`: status=`pass`, required=`required`, duration=`1s`
  - note: Runs TerraV1 fixture suite to validate schema/runtime fixture integrity and package resource wiring.
  - log: `/Users/chriskarani/CodingProjects/Terra/Artifacts/rc-hardening/latest/fixture-hygiene.log`
- `static-audits`: status=`pass`, required=`required`, duration=`0s`
  - note: Verifies terra.v1 contract source and 403/400 reject semantics in OTLP server.
  - log: `/Users/chriskarani/CodingProjects/Terra/Artifacts/rc-hardening/latest/static-audits.log`

## Go / No-Go
- Verdict: **GO**
