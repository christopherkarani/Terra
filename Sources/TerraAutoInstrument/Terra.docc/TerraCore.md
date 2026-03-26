# Terra Core

## One Request, One Root

```swift
let answer = try await Terra.workflow(name: "request", id: "req-1") { workflow in
  workflow.event("request.start")
  let draft = try await workflow.infer("gpt-4o-mini", prompt: "Plan") { "draft" }
  let tool = try await workflow.tool("search", callId: "search-1") { "docs" }
  return draft + tool
}
```

## Transcript Workflows

```swift
var messages = [Terra.ChatMessage(role: "user", content: "Plan the fix.")]

let result = try await Terra.workflow(name: "planner", messages: &messages) { workflow, transcript in
  workflow.checkpoint("planning")
  await transcript.append(.init(role: "assistant", content: "Draft plan"))
  return "ok"
}
```

## Manual Lifecycle

```swift
let parent = Terra.startSpan(name: "manual.request")
defer { parent.end() }

_ = try await Terra.tool("search", callId: "manual-1").under(parent).run { "ok" }
```
