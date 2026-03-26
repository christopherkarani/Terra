# Canonical API

Use the composable call API as the canonical path for single operations, and use Terra's manual tracing surface when one agentic workflow must own multiple child operations.

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
- ``Terra/Operation/under(_:)``
- ``Terra/Operation/run(_:)-6bghi``
- ``Terra/Operation/run(_:)-swift.method``

## Lifecycle Entry Points

- ``Terra/start(_:)``
- ``Terra/shutdown()``
- ``Terra/reconfigure(_:)``
- ``Terra/agentic(name:id:_:)``
- ``Terra/trace(name:id:_:)-swift.method``
- ``Terra/startSpan(name:id:attributes:)``

## Quick Example

```swift
import Terra

try await Terra.quickStart()
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

## Agentic Root Example

Use `Terra.agentic` when a planner loop, tool chain, or detached helper must stay under one long-lived root span.

```swift
import Terra

let answer = try await Terra.agentic(name: "planner", id: "issue-42") { agent in
  agent.checkpoint("plan")

  let plan = try await agent.infer("gpt-4o-mini", prompt: "Plan the fix.") {
    "Investigate and patch"
  }

  let docs = try await agent.tool("search", callId: "tool-call-1") {
    "Relevant documentation"
  }

  agent.event("complete")
  return plan + docs
}
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

When child work must bind to a chosen parent span explicitly, attach it with ``Terra/Operation/under(_:)``:

```swift
import Terra

let parent = Terra.startSpan(name: "background-sync")
defer { parent.end() }

let results = try await Terra
  .tool("search", callId: "tool-call-2")
  .under(parent)
  .run { "result for query" }
```

## Next Guides

- Typed IDs: <doc:Typed-IDs>
- Metadata builder patterns: <doc:Metadata-Builder>
- Stable lifecycle errors: <doc:TerraError-Model>
- Protocol seams and deterministic engines: <doc:TelemetryEngine-Injection>
- Discovery helpers and manual spans: <doc:API-Reference>
