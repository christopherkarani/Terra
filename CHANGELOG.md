# Changelog

All notable changes to this repository will be documented in this file.

Terra follows [Semantic Versioning](https://semver.org/).

## Unreleased

### API Stability

- **Canonical startup**: `Terra.start()` is the single recommended entry point:
  - `Terra.start()` — zero-arg quickstart
  - `Terra.start(_ preset:configure:)` — preset with overrides
  - `Terra.start(_ config: Configuration)` — explicit flat configuration
  - `Terra.start(_ config: AutoInstrumentConfiguration)` — advanced escape hatch
- **Renamed**: `Terra.V3Configuration` → `Terra.Configuration`. A deprecated typealias preserves source compatibility.
- **Deprecated**:
  - `Terra.bootstrap(_:configure:)` — use `Terra.start(_:configure:)` instead
  - `Terra.start(preset:configure:)` (named label) — use unlabeled version
  - `Terra.enable(_:)` / `Terra.configure(_:)` — already deprecated, updated messages
- **Deprecation policy**: Deprecated APIs emit compile-time warnings for at least 2 minor releases before removal in the next major version.

### Added

- `Terra.start(_ preset:configure:)` overload for cleaner preset-driven startup calls.
- Typed inference/streaming telemetry helpers:
  - `scope.setRuntime(_:)`
  - `scope.setProvider(_:)`
  - `scope.setResponseModel(_:)`
  - `scope.setTokenUsage(input:output:)`
  - `stream.recordChunk(tokens:)`

### Fixed

- `withStreamingInferenceSpan(model:...)` convenience overload signature to accept `StreamingInferenceScope`.
