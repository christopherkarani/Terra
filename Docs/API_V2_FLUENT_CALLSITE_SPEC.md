# Terra V2 Fluent Call-Site Spec (Legacy Snapshot)

> Historical reference only. For the canonical current API see [`Docs/Front_Facing_API.md`](./Front_Facing_API.md).
> Current public operation entry points are `Terra.infer`, `Terra.stream`, `Terra.embed`, `Terra.agent`, `Terra.tool`, and `Terra.safety`.

Terra v2 uses fluent operation builders that end with `.run { ... }`.

## Canonical shape

```swift
let result = try await Terra
  .inference(model: "llama-3.2", prompt: prompt)
  .provider("openai-compatible")
  .runtime("mlx")
  .run {
    try await model.generate()
  }
```

## Entry points

- `Terra.enable(_:)`
- `Terra.configure(_:)`
- `Terra.shared() -> Session`

## Operation builders

- `Terra.inference(...) -> InferenceCall`
- `Terra.stream(...) -> StreamingCall`
- `Terra.embedding(...) -> EmbeddingCall`
- `Terra.agent(...) -> AgentCall`
- `Terra.tool(...) -> ToolCall`
- `Terra.safetyCheck(...) -> SafetyCheckCall`

Each call object supports fluent metadata methods and two run overloads:

- `.run { ... }`
- `.run { trace in ... }`

## Typed extension points

- `AttributeKey<Value: TelemetryValue>`
- `AttributeBag`
- `TerraEvent`

## Hard break removals

The following APIs are no longer public in v2:

- `withInferenceSpan`
- `withStreamingInferenceSpan`
- `withEmbeddingSpan`
- `withAgentInvocationSpan`
- `withToolExecutionSpan`
- `withSafetyCheckSpan`
