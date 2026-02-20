# Terra Telemetry Convention Governance

## 1. Canonical Source

`Docs/TelemetryConvention/terra-v1.md` is the canonical public specification for
`terra.v1` on-device inference telemetry.

`Docs/TelemetryConvention/terra-v1.schema.json` is the machine-readable baseline
and must reflect the markdown spec.

## 2. Versioning

- `terra.semantic.version` uses major/minor style (`v1`, `v1.1`).
- Contract-breaking changes require a new major version and coordinated rollout.
- Minor changes add fields/attrs with backward compatible defaults.
- During development, breaking changes are tracked with explicit migration notes in `CHANGELOG.md`.

## 3. Change Control

- Every schema-affecting change requires:
  - rationale,
  - affected runtimes,
  - sample fixtures updates (new/updated files under `Tests/TerraTraceKitTests/Fixtures/TerraV1`),
  - and test coverage in `Tests/TerraTraceKitTests`.
- CI must fail when required fixture coverage drops or contract tests cannot parse.

## 4. Runtime Parity Rules

- All first-class runtimes must satisfy:
  - canonical `terra.runtime` value,
  - required contract attributes,
  - streaming attribution for streamed responses,
  - and recommendation/anomaly signal compatibility.

## 5. Security and Privacy

- Deterministic redaction/anonymization policies are part of the same release when
  telemetry schema changes.
- Export-control behavior and policy-blocked ingestion must remain documented in the same spec revision.

## 6. Escalation Criteria

- Regressions in decoding, event cardinality limits, or schema mismatch handling
  are considered release-blocking.
- Missing fixture coverage for any canonical runtime is release-blocking.
