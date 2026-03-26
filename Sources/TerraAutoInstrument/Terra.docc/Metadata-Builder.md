# Metadata

Use `SpanHandle` everywhere Terra gives you a closure handle.

```swift
let value = try await Terra.workflow(name: "request") { workflow in
  workflow.attribute("request.id", "req-1")
  workflow.tokens(input: 12, output: 18)
  workflow.responseModel("gpt-4o-mini")
  return "ok"
}
```

For streaming child spans:

```swift
let value = try await Terra.workflow(name: "stream.request") { workflow in
  try await workflow.stream("gpt-4o-mini", prompt: "Explain") { span in
    span.firstToken()
    span.chunk(4)
    span.outputTokens(12)
    return "ok"
  }
}
```
