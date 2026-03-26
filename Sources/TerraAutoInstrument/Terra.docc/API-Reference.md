# API Reference

Complete reference for Terra's workflow-first public API.

## Primary Path

New integrations should follow this sequence:

1. ``Terra/quickStart()``
2. ``Terra/help()``
3. ``Terra/diagnose()``
4. ``Terra/workflow(name:id:_:)-swift.method`` or ``Terra/workflow(name:id:messages:_:)-swift.method``
5. ``Terra/startSpan(name:id:attributes:)`` only when lifecycle must outlive one closure

## Root APIs

### Workflow Root

```swift
let value = try await Terra.workflow(name: "request", id: "req-1") { workflow in
  workflow.event("request.start")
  return "ok"
}
```

Use ``Terra/workflow(name:id:_:)-swift.method`` when one request should appear as one root workflow with child operations beneath it.

### Workflow With Transcript

```swift
var messages = [Terra.ChatMessage(role: "user", content: "Plan the fix.")]

let value = try await Terra.workflow(name: "planner", messages: &messages) { workflow, transcript in
  workflow.checkpoint("planning")
  await transcript.append(.init(role: "assistant", content: "Draft plan"))
  return "ok"
}
```

Use ``Terra/workflow(name:id:messages:_:)-swift.method`` when the root workflow must mutate transcript state safely across async boundaries.

### Manual Span

```swift
let span = Terra.startSpan(name: "manual-parent")
span.event("queued")
span.end()
```

Use ``Terra/startSpan(name:id:attributes:)`` only when later work must attach to a parent that outlives the current closure.

## SpanHandle

``Terra/SpanHandle`` is the single public annotation and parenting surface.

Key methods:

- `event(_:)`
- `attribute(_:_:)`
- `tokens(input:output:)`
- `responseModel(_:)`
- `recordError(_:)`
- `checkpoint(_:)`
- `end()`
- `detached(priority:_:)`

Child helpers on the handle:

- `infer`
- `stream`
- `tool`
- `embed`
- `safety`
- `agent`

Example:

```swift
try await Terra.workflow(name: "chat") { workflow in
  let answer = try await workflow.infer("gpt-4o-mini", prompt: "Hello") { span in
    span.tokens(input: 4, output: 9)
    span.responseModel("gpt-4o-mini")
    return "Hi"
  }
  return answer
}
```

## Operation Factories

Terra's child operation factories return ``Terra/Operation``:

- ``Terra/infer(_:prompt:provider:runtime:temperature:maxTokens:)``
- ``Terra/stream(_:prompt:provider:runtime:temperature:maxTokens:expectedTokens:)``
- ``Terra/embed(_:inputCount:provider:runtime:)``
- ``Terra/agent(_:id:provider:runtime:)``
- ``Terra/tool(_:callId:type:provider:runtime:)``
- ``Terra/safety(_:subject:provider:runtime:)``

Operation modifiers:

- `capture(_:)`
- `under(_:)`
- `run(_:)`

`run` closures receive ``Terra/SpanHandle``:

```swift
let value = try await Terra
  .tool("search", callId: "call-1")
  .run { span in
    span.event("tool.start")
    return "docs"
  }
```

## Transcript Support

``Terra/WorkflowTranscript`` provides buffered transcript mutation for workflow roots with messages:

- `snapshot()`
- `replace(with:)`
- `append(_:)`
- `append(contentsOf:)`
- `clear()`

Writeback occurs on both success and throw.

## Identifiers

Public typed wrappers retained for stable metadata labeling:

- ``Terra/ProviderID``
- ``Terra/RuntimeID``

Model names and tool call identifiers are plain `String` values.

## Guidance

- Use `workflow` for the normal one-request root.
- Use `workflow(..., messages:)` when transcript mutation is part of the root workflow.
- Use `startSpan` only for explicit long-lived parent control.
- Use `SpanHandle.detached(...)` instead of raw `Task.detached` when parent trace linkage matters.
