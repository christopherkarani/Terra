# Quickstart in 90 Seconds

```swift
print(Terra.help())
let report = Terra.diagnose()
```

```swift
let answer = try await Terra.workflow(name: "status.update", id: "demo-1") { workflow in
  try await workflow.infer("gpt-4o-mini", prompt: "Summarize the release") { span in
    span.tokens(input: 24, output: 12)
    return "ok"
  }
}
```

If the model emits a tool call that will execute after the child inference or stream
closure returns, capture `try span.handoff().tool(...)` before that child span ends.
