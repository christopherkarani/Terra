# Terra

Terra is a Swift telemetry SDK for tracing AI workflows, tools, inference, streaming, embeddings, and safety checks.

## Start Here

```swift
print(Terra.help())
let report = Terra.diagnose()
```

## Canonical Root

Use one workflow root per request:

```swift
let answer = try await Terra.workflow(name: "chat.request", id: "req-1") { workflow in
  workflow.event("request.received")

  let draft = try await workflow.infer(
    "gpt-4o-mini",
    prompt: "Summarize the latest issue"
  ) { span in
    span.tokens(input: 24, output: 14)
    return "draft"
  }

  let toolResult = try await workflow.tool(
    "search",
    callId: "search-1",
    type: "web_search"
  ) { span in
    span.event("tool.invoked")
    return "docs"
  }

  return draft + toolResult
}
```

## Mutable Transcript

Use the transcript overload when the workflow owns chat history mutation:

```swift
var messages = [Terra.ChatMessage(role: "user", content: "Plan the fix.")]

let result = try await Terra.workflow(name: "planner", messages: &messages) { workflow, transcript in
  workflow.checkpoint("planning")
  await transcript.append(.init(role: "assistant", content: "Draft plan"))
  return "ok"
}
```

## Streaming

Keep streaming under a workflow root. The stream span finalizes chunk and output-token
metrics when the streaming closure returns or throws:

```swift
let streamed = try await Terra.workflow(name: "stream.request") { workflow in
  try await workflow.stream("gpt-4o-mini", prompt: "Explain") { span in
    span.firstToken()
    span.chunk(4)
    span.outputTokens(12)
    return "done"
  }
}
```

## Deferred Tool After Stream

If a tool call is discovered inside a child inference/stream span but executed later,
hand it off to the wider parent before the child closes:

```swift
let answer = try await Terra.workflow(name: "stream.and.tool") { workflow in
  let deferred = try await workflow.stream("gpt-4o-mini", prompt: "Explain") { span in
    span.firstToken()
    span.chunk(4)
    return try span.handoff().tool("search", callId: "search-1", type: "web_search")
  }

  let toolResult = try await deferred.run { "docs" }
  return toolResult
}
```

## Manual Parent

Use manual lifecycle only when even the workflow root cannot own the whole request:

```swift
let parent = Terra.startSpan(name: "manual.request")
defer { parent.end() }

_ = try await Terra.tool("search", callId: "manual-1").under(parent).run { "ok" }
```

## Discovery

- `Terra.help()`
- `Terra.diagnose()`
- `Terra.ask("workflow with tools")`
- `Terra.examples()`
- `Terra.guides()`
- `Terra.playground()`
