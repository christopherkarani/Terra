# Canonical API

Terra is workflow-first.

## Root Request

```swift
let value = try await Terra.workflow(name: "request", id: "req-1") { workflow in
  workflow.event("request.start")
  return "ok"
}
```

## Root With Transcript

```swift
var messages = [Terra.ChatMessage(role: "user", content: "Plan the fix.")]

let value = try await Terra.workflow(name: "planner", messages: &messages) { workflow, transcript in
  workflow.checkpoint("planning")
  await transcript.append(.init(role: "assistant", content: "Draft plan"))
  return "ok"
}
```

## Child Operations

```swift
let value = try await Terra.workflow(name: "request") { workflow in
  let draft = try await workflow.infer("gpt-4o-mini", prompt: "Plan") { "draft" }
  let tool = try await workflow.tool("search", callId: "search-1") { "docs" }
  return draft + tool
}
```

## Deferred Tool After Stream

```swift
let value = try await Terra.workflow(name: "request") { workflow in
  let deferred = try await workflow.stream("gpt-4o-mini", prompt: "Explain") { span in
    span.firstToken()
    return try span.handoff().tool("search", callId: "search-1")
  }
  return try await deferred.run { "docs" }
}
```

## Manual Lifecycle

```swift
let span = Terra.startSpan(name: "manual")
span.event("queued")
span.end()
```
