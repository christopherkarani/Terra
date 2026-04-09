# Changelog

All notable changes to this repository will be documented in this file.

Terra follows [Semantic Versioning](https://semver.org/).

## Unreleased

### Breaking

- Canonical startup and configuration path is now `Terra.start()` + `Terra.Configuration`.
  Migration: replace legacy `enable/configure/bootstrap` entry points with `Terra.start(...)`.
- Closure-first span factories are the primary API surface.
  Migration: prefer `Terra.inference { ... }`, `Terra.agent { ... }`, etc. over legacy wrappers.
- Privacy defaults are now policy-driven via `Terra.PrivacyPolicy` with `.redacted` as the default behavior.
  Migration: move previous content policy/redaction wiring to `Terra.Configuration.privacy`.

### Added

- v3 fluent APIs for all span types:
  - `Terra.inference(...)`
  - `Terra.stream(...)`
  - `Terra.agent(...)`
  - `Terra.tool(...)`
  - `Terra.embedding(...)`
  - `Terra.safetyCheck(...)`
- Builder escape hatch with `.execute { ... }` terminal and `.includeContent()` per-call override.
- `Terra.Trace` protocol and `TerraTraceable` integration for typed result enrichment.
- Typed telemetry constants under `Terra.Key` namespaces.
- `@Traced` macro coverage for model, stream, agent, tool, embedding, and safety instrumentation.
- Foundation Models wrapper (`Terra.TracedSession`) enhancements:
  - transcript-diff tool call/result capture
  - guardrail safety span emission
  - generation option attribute capture
- API parity tests covering closure-first vs builder-execute behavior across all six span types.
- Privacy audit test suite covering all major content-bearing call paths.

### Changed

- `Terra.V3Configuration` consolidated into `Terra.Configuration` as the single canonical config type.
- `Terra.LifecycleState` and runtime lifecycle handling hardened for start/shutdown/restart behavior.
- Wrapper provider semantics aligned:
  - `TerraMLX` → `gen_ai.provider.name = "mlx"`
  - `TerraLlama` → `gen_ai.provider.name = "llama.cpp"`
  - Foundation Models → `gen_ai.provider.name = "apple/foundation-model"`
- README and docs now lead with v3 APIs only.

### Deprecated

- Startup/configuration compatibility APIs:
  - `Terra.enable(...)`
  - `Terra.configure(...)`
  - `Terra.bootstrap(...)`
  - legacy `Terra.start(preset:...)` label forms
- Legacy config aliases:
  - `AutoInstrumentConfiguration`
  - `StartProfile`
- Builder compatibility shims:
  - `.run { ... }` (use `.execute { ... }`)
  - `.capture(.optIn)` (use `.includeContent()`)
- Legacy helper entry points are retained with forwarding implementations and guidance in deprecation messages.

### Fixed

- Privacy audit remediation H-1: `exception.message` is now gated by content policy and omitted when content capture is disallowed.
- Privacy audit remediation H-2: HMAC-SHA256 redaction is the default hashing path for redacted content in non-legacy paths.
- OpenClaw audit remediation M-1: default gateway hosts are no longer enabled when OpenClaw mode is `.disabled`.
- API cleanup: internal usage migrated from deprecated `.run` to `.execute` and from `.capture` to `.includeContent`.
- Android SDK unit tests no longer compile instrumentation-only sources through the main source set.
- Android host-side resource collection now falls back to JVM attributes unless the SDK is actually running on an Android runtime.
