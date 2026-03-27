# Terra Migration Guide

This release is a deliberate workflow-first breaking cleanup.

## What Changed

- Root tracing now starts with `Terra.workflow(...)`
- Transcript-owning roots now use `Terra.workflow(..., messages: &messages)`
- Explicit long-lived parents still use `Terra.startSpan(...)`
- `Operation.run` closures now receive `SpanHandle`
- Model names and tool call identifiers are plain `String` values
- `ProviderID` and `RuntimeID` remain

Removed public compatibility surface:

- `Terra.trace(...)`
- `Terra.agentic(...)`
- `Terra.loop(...)`
- `TraceHandle`
- `TraceBuilder`
- `ModelID`
- `ToolCallID`
- `callID:`

## API Mapping

| Old shape | New shape |
| --- | --- |
| `Terra.trace(name:id:_:)` | `Terra.workflow(name:id:_:)` |
| `Terra.loop(name:id:messages:_:)` | `Terra.workflow(name:id:messages:_:)` |
| `Terra.agentic(name:id:_:)` | `Terra.workflow(name:id:_:)` plus `SpanHandle` child helpers |
| `TraceHandle` in `.run { ... }` | `SpanHandle` in `.run { ... }` |
| `trace.tag(...)` | `span.attribute(...)` |
| `Terra.ModelID("...")` | raw `String` model name |
| `Terra.ToolCallID("...")` | raw `String` `callId` |
| `callID:` | `callId:` |

## Root Workflow Migration

### Before

```swift
let value = try await Terra.agentic(name: "planner", id: "issue-42") { agent in
  let draft = try await agent.infer("gpt-4o-mini", prompt: "Plan") { "draft" }
  let docs = try await agent.tool("search", callId: "call-1") { "docs" }
  return draft + docs
}
```

### After

```swift
let value = try await Terra.workflow(name: "planner", id: "issue-42") { workflow in
  let draft = try await workflow.infer("gpt-4o-mini", prompt: "Plan") { "draft" }
  let docs = try await workflow.tool("search", callId: "call-1") { "docs" }
  return draft + docs
}
```

## Transcript Workflow Migration

### Before

```swift
let result = try await Terra.loop(name: "planner", messages: &messages) { loop in
  await loop.appendMessage(.init(role: "assistant", content: "draft"))
  return "ok"
}
```

### After

```swift
let result = try await Terra.workflow(name: "planner", messages: &messages) { workflow, transcript in
  workflow.checkpoint("planning")
  await transcript.append(.init(role: "assistant", content: "draft"))
  return "ok"
}
```

## Composable Operation Migration

### Before

```swift
let answer = try await Terra
  .infer("gpt-4o-mini", prompt: prompt)
  .run { trace in
    trace.tag("app.user_tier", "pro")
    trace.event("request.start")
    return try await llm.generate(prompt)
  }
```

### After

```swift
let answer = try await Terra
  .infer("gpt-4o-mini", prompt: prompt)
  .run { span in
    span.attribute("app.user_tier", "pro")
    span.event("request.start")
    return try await llm.generate(prompt)
  }
```

## Detached Work

Use `SpanHandle.detached(...)` when parent linkage matters across detached tasks.
If the work must outlive the current closure entirely, create an explicit parent with `Terra.startSpan(...)`.
If a tool call is discovered inside an inference or stream child span but executed later,
capture `try span.handoff().tool(...)` or use `try await span.withToolParent { parent in ... }`
before the child closure returns.

## Recommended Migration Order

1. Replace all root `trace` / `loop` / `agentic` calls with `workflow`
2. Replace `TraceHandle` usage with `SpanHandle`
3. Replace `tag(...)` with `attribute(...)`
4. Replace typed model/tool IDs with raw `String` values
5. Replace any lingering `callID:` labels with `callId:`
6. Run `Terra.help()`, `Terra.diagnose()`, and your trace tests to confirm the new hierarchy
