# Canonical API

Use the composable call API as the canonical path.

## Operation Factories

- ``TerraCore/Terra/infer(_:prompt:provider:runtime:temperature:maxTokens:)``
- ``TerraCore/Terra/stream(_:prompt:provider:runtime:temperature:maxTokens:expectedTokens:)``
- ``TerraCore/Terra/embed(_:inputCount:provider:runtime:)``
- ``TerraCore/Terra/agent(_:id:provider:runtime:)``
- ``TerraCore/Terra/tool(_:callID:type:provider:runtime:)``
- ``TerraCore/Terra/safety(_:subject:provider:runtime:)``

## Shared Call Pipeline

All factories return ``TerraCore/Terra/Call``.

Common composition methods:

- ``TerraCore/Terra/Call/capture(_:)``
- ``TerraCore/Terra/Call/attr(_:_:)``
- ``TerraCore/Terra/Call/metadata(_:)``
- ``TerraCore/Terra/Call/run(_:)``
- ``TerraCore/Terra/Call/run(using:_:)``

## Lifecycle Entry Points

- ``TerraCore/Terra/start(_:)``
- ``TerraCore/Terra/shutdown()``
- ``TerraCore/Terra/reconfigure(_:)``

## Quick Example

```swift
import Terra

try await Terra.start(.init(preset: .quickstart))
let answer = try await Terra
  .infer(
    Terra.ModelID("gpt-4o-mini"),
    prompt: "Summarize this changelog in one sentence.",
    provider: Terra.ProviderID("openai"),
    runtime: Terra.RuntimeID("http_api")
  )
  .run {
    "Release summary"
  }
await Terra.shutdown()
```

## Next Guides

- Typed IDs: <doc:Typed-IDs>
- Metadata builder patterns: <doc:Metadata-Builder>
- Stable lifecycle errors: <doc:TerraError-Model>
- Protocol seams and deterministic engines: <doc:TelemetryEngine-Injection>
