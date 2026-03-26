# Canonical API

Use the composable call API as the canonical path.

## Operation Factories

- ``Terra/infer(_:prompt:provider:runtime:temperature:maxTokens:)``
- ``Terra/stream(_:prompt:provider:runtime:temperature:maxTokens:expectedTokens:)``
- ``Terra/embed(_:inputCount:provider:runtime:)``
- ``Terra/agent(_:id:provider:runtime:)``
- ``Terra/tool(_:callId:type:provider:runtime:)``
- ``Terra/safety(_:subject:provider:runtime:)``

## Shared Operation Pipeline

All factories return ``Terra/Operation``.

Common composition methods:

- ``Terra/Operation/capture(_:)``
- ``Terra/Operation/run(_:)-6bghi``
- ``Terra/Operation/run(_:)-swift.method``

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
    "gpt-4o-mini",
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
    callId: "tool-call-1",
    type: "web_search",
    provider: Terra.ProviderID("openai"),
    runtime: Terra.RuntimeID("http_api")
  )
  .run { trace in
    trace.event("tool.invoked")
    trace.tag("sample.kind", "tool")
    return ["result for query"]
  }
```

## Next Guides

- Typed IDs: <doc:Typed-IDs>
- Metadata builder patterns: <doc:Metadata-Builder>
- Stable lifecycle errors: <doc:TerraError-Model>
- Protocol seams and deterministic engines: <doc:TelemetryEngine-Injection>
