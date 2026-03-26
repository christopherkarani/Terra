# CoreML Integration

Use Terra workflow roots around the request that owns CoreML inference:

```swift
let result = try await Terra.workflow(name: "coreml.request") { workflow in
  try await workflow.infer("local-coreml-model", prompt: "Classify this image") { span in
    span.responseModel("local-coreml-model")
    return "ok"
  }
}
```

Use `Terra.startSpan(...)` only when the parent must outlive the closure.
