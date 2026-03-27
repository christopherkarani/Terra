# Integrations

## Foundation Models

Use `TerraTracedSession` with string model identifiers:

```swift
let session = TerraTracedSession(modelIdentifier: "apple/foundation-model")
let answer = try await session.respond(to: "Summarize this note")
```

Wrap it in `Terra.workflow(...)` when the session is one step inside a wider request,
and use `span.handoff()` if that surrounding workflow needs to execute a later Terra
tool call after a child inference or stream span closes.

## MLX

```swift
let answer = try await TerraMLX.traced(model: "mlx-community/Llama-3.2-1B") {
  "ok"
}
```

## CoreML

Wrap the wider request in a workflow root, then record model work inside it:

```swift
let answer = try await Terra.workflow(name: "coreml.request") { workflow in
  try await workflow.infer("local-coreml-model", prompt: "Classify") { span in
    span.responseModel("local-coreml-model")
    return "ok"
  }
}
```

Use `Terra.startSpan(...)` only when the parent must outlive the wider workflow body.
If tool work is discovered inside a child inference or stream span but runs later,
capture `span.handoff()` before the child span ends.
