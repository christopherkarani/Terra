# Canonical API

Terra’s primary surface is the composable call API:

- ``Terra/infer(_:prompt:provider:runtime:temperature:maxTokens:)``
- ``Terra/stream(_:prompt:provider:runtime:temperature:maxTokens:expectedTokens:)``
- ``Terra/embed(_:inputCount:provider:runtime:)``
- ``Terra/agent(_:id:provider:runtime:)``
- ``Terra/tool(_:callID:type:provider:runtime:)``
- ``Terra/safety(_:subject:provider:runtime:)``

## Quickstart

```swift
import Terra

try await Terra.start(.init(preset: .quickstart))
let answer = try await Terra
  .infer(Terra.ModelID("gpt-4o-mini"), prompt: "Say hello")
  .run { "Hello" }
await Terra.shutdown()
```

## Shared Call Composition

All canonical factories return ``Terra/Call``.

Use:

- ``Terra/Call/capture(_:)``
- ``Terra/Call/attr(_:_:)``
- ``Terra/Call/metadata(_:)``
- ``Terra/Call/run(_:)``
- ``Terra/Call/run(using:_:)``

## Typed Identifiers

Prefer typed IDs across public API calls:

- ``Terra/ModelID``
- ``Terra/ProviderID``
- ``Terra/RuntimeID``
- ``Terra/ToolCallID``

## Stable Public Errors

Lifecycle public throws use ``Terra/TerraError`` and deterministic ``Terra/TerraError/Code`` values.
