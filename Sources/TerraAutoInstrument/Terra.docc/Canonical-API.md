# Canonical API

Use the composable call API as the canonical path.

## Operation Factories

- ``Terra/infer(_:prompt:provider:runtime:temperature:maxTokens:)``
- ``Terra/stream(_:prompt:provider:runtime:temperature:maxTokens:expectedTokens:)``
- ``Terra/embed(_:inputCount:provider:runtime:)``
- ``Terra/agent(_:id:provider:runtime:)``
- ``Terra/tool(_:callID:type:provider:runtime:)``
- ``Terra/safety(_:subject:provider:runtime:)``

## Shared Call Pipeline

All factories return ``Terra/Call``.

Common composition methods:

- ``Terra/Call/capture(_:)``
- ``Terra/Call/attr(_:_:)``
- ``Terra/Call/metadata(_:)``
- ``Terra/Call/run(_:)``
- ``Terra/Call/run(using:_:)``

## Lifecycle Entry Points

- ``Terra/start(_:)``
- ``Terra/shutdown()``
- ``Terra/reconfigure(_:)``

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

## Reusable Examples

These recipes are directly reusable from `Examples/Terra Sample/RecipeSnippets.swift`.

```swift
import Terra

let results = try await Terra
  .tool(
    "search",
    callID: Terra.ToolCallID("tool-call-1"),
    type: "web_search",
    provider: Terra.ProviderID("openai"),
    runtime: Terra.RuntimeID("http_api")
  )
  .metadata {
    Terra.event("tool.invoked")
    Terra.attr(.init("sample.kind"), "tool")
  }
  .run { _ in
    ["result for query"]
  }
```

## Next Guides

- Typed IDs: <doc:Typed-IDs>
- Metadata builder patterns: <doc:Metadata-Builder>
- Stable lifecycle errors: <doc:TerraError-Model>
- Protocol seams and deterministic engines: <doc:TelemetryEngine-Injection>
