# Integrations

## Foundation Models

Use `TerraTracedSession` with string model identifiers:

```swift
let session = TerraTracedSession(modelIdentifier: "apple/foundation-model")
let answer = try await session.respond(to: "Summarize this note")
```

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
