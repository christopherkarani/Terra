# Canonical API

Terra's public story is trace-first.

Use ``Terra/trace(name:id:_:)-swift.method`` for most single-root tasks. Use ``Terra/loop(name:id:messages:_:)`` when a workflow needs one root span plus in-place transcript updates. Use ``Terra/agentic(name:id:_:)`` for multi-step planners and tool orchestration. Use ``Terra/startSpan(name:id:attributes:)`` only when span lifecycle must outlive the current closure and be ended manually.

The operation factories remain available, but they are secondary convenience APIs rather than the main entry point.

## Start Here

- ``Terra/quickStart()``
- ``Terra/help()``
- ``Terra/diagnose()``

## Primary Root APIs

- ``Terra/trace(name:id:_:)-swift.method``
- ``Terra/loop(name:id:messages:_:)``
- ``Terra/agentic(name:id:_:)``
- ``Terra/startSpan(name:id:attributes:)``

## Secondary Operation Helpers

- ``Terra/infer(_:prompt:provider:runtime:temperature:maxTokens:)``
- ``Terra/stream(_:prompt:provider:runtime:temperature:maxTokens:expectedTokens:)``
- ``Terra/embed(_:inputCount:provider:runtime:)``
- ``Terra/agent(_:id:provider:runtime:)``
- ``Terra/tool(_:callId:type:provider:runtime:)``
- ``Terra/safety(_:subject:provider:runtime:)``
- ``Terra/Operation/capture(_:)``
- ``Terra/Operation/under(_:)``
- ``Terra/Operation/run(_:)-swift.method``

`Operation.run { trace in ... }` still passes ``Terra/TraceHandle`` for compatibility. When Terra owns the underlying span, `trace.span` exposes the active ``Terra/SpanHandle``.

## Quick Example

```swift
import Terra

try await Terra.quickStart()

let answer = try await Terra.trace(name: "release.summary", id: "changelog-1") { span in
  span.event("summary.started")
  span.attribute("app.surface", "settings")
  span.tokens(input: 42, output: 18)
  span.responseModel("gpt-4o-mini")
  return "Release summary"
}

await Terra.shutdown()
```

## Mutable Transcript Loop

Use ``Terra/loop(name:id:messages:_:)`` when the caller owns an `inout` transcript and the body must remain `@Sendable`.

```swift
import Terra

var messages: [Terra.ChatMessage] = [
  .init(role: "user", content: "Plan the fix.")
]

let plan = try await Terra.loop(name: "planner.loop", id: "issue-42", messages: &messages) { loop in
  loop.checkpoint("planning")
  await loop.appendMessage(.init(role: "assistant", content: "Draft plan"))
  return "Plan ready"
}
```

## Agentic Root Example

Use ``Terra/agentic(name:id:_:)`` when a planner loop, tool chain, or detached helper must stay under one long-lived root span.

```swift
import Terra

let answer = try await Terra.agentic(name: "planner", id: "issue-42") { agent in
  agent.checkpoint("plan")

  let plan = try await agent.infer(
    "gpt-4o-mini",
    messages: [
      .init(role: "system", content: "You plan small code changes."),
      .init(role: "user", content: "Plan the fix.")
    ]
  ) {
    "Investigate and patch"
  }

  let docs = try await agent.tool("search", callId: "tool-call-1") {
    "Relevant documentation"
  }

  agent.event("complete")
  return plan + docs
}
```

## Manual Lifecycle Example

Use ``Terra/startSpan(name:id:attributes:)`` when the parent span must outlive the current closure and child work should attach explicitly.

```swift
import Terra

let parent = Terra.startSpan(name: "background-sync")
defer { parent.end() }

let results = try await Terra
  .tool("search", callId: "tool-call-2")
  .under(parent)
  .run { "result for query" }
```

## Operation Helper Example

The fluent helper APIs still work well for isolated inference, streaming, embedding, tool, and safety spans.

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

If detached work starts after an explicit parent span already ended, Terra still runs the detached task and records a `detached.parent.ended` event on the first replacement span.

## Next Guides

- Quickstart: <doc:Quickstart-90s>
- Runtime concepts: <doc:TerraCore>
- Metadata patterns: <doc:Metadata-Builder>
- Stable lifecycle errors: <doc:TerraError-Model>
- Full symbol reference: <doc:API-Reference>
