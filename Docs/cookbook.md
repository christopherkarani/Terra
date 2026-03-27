# Terra Cookbook

## Chat Request

```swift
let answer = try await Terra.workflow(name: "chat.request", id: "req-1") { workflow in
  try await workflow.infer("gpt-4o-mini", prompt: "Summarize this thread") { span in
    span.tokens(input: 20, output: 12)
    return "summary"
  }
}
```

## Streaming Generation

```swift
let answer = try await Terra.workflow(name: "chat.stream", id: "req-2") { workflow in
  try await workflow.stream("gpt-4o-mini", prompt: "Explain the fix") { span in
    span.firstToken()
    span.chunk(5)
    span.outputTokens(18)
    return "streamed"
  }
}
```

The stream span closes and writes its final streaming metrics when the closure returns.
If a tool call is emitted during streaming but executed later, capture a handoff first.

## Deferred Tool Handoff

```swift
let result = try await Terra.workflow(name: "tool.after.stream", id: "req-2b") { workflow in
  let deferred = try await workflow.stream("gpt-4o-mini", prompt: "Explain the fix") { span in
    span.firstToken()
    span.chunk(5)
    return try span.handoff().tool("search", callId: "search-2", type: "web_search")
  }

  return try await deferred.run { "docs" }
}
```

## Tool Execution

```swift
let result = try await Terra.workflow(name: "tool.request", id: "req-3") { workflow in
  try await workflow.tool("search", callId: "search-1", type: "web_search") { span in
    span.event("tool.invoked")
    return "docs"
  }
}
```

## Agent Loop

```swift
let result = try await Terra.workflow(name: "agent.request", id: "req-4") { workflow in
  workflow.checkpoint("planning")
  let draft = try await workflow.infer("gpt-4o-mini", prompt: "Plan") { "draft" }
  let lookup = try await workflow.tool("search", callId: "search-2") { "lookup" }
  return draft + lookup
}
```

## Mutable Transcript

```swift
var messages = [Terra.ChatMessage(role: "user", content: "Plan the fix.")]

let result = try await Terra.workflow(name: "planner", messages: &messages) { workflow, transcript in
  workflow.checkpoint("planning")
  await transcript.append(.init(role: "assistant", content: "Draft plan"))
  return "ok"
}
```

## Detached Work

```swift
let value = try await Terra.workflow(name: "background.sync") { workflow in
  let task = workflow.detached { detached in
    detached.event("background.started")
    return "ok"
  }
  return try await task.value
}
```

## Manual Parent

```swift
let parent = Terra.startSpan(name: "manual.parent")
defer { parent.end() }

_ = try await Terra.tool("search", callId: "manual-1").under(parent).run { "ok" }
```
