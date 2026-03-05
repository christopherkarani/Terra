# Terra Migration Guide (Legacy -> Current)

This guide migrates existing integrations to the canonical composable API:

- Startup: `Terra.start(...)`
- Operations: `Terra.infer/stream/embed/agent/tool/safety`
- Terminal: `.run { ... }`
- Metadata: `.attr(...)`
- Per-call content capture: `.capture(.includeContent)`

## API Mapping

| Legacy API | Current replacement |
| --- | --- |
| `withInferenceSpan(...)` | `Terra.infer(...).run { ... }` |
| `withStreamingInferenceSpan(...)` | `Terra.stream(...).run { trace in ... }` |
| `withAgentInvocationSpan(...)` | `Terra.agent(...).run { ... }` |
| `withToolExecutionSpan(...)` | `Terra.tool(...).run { ... }` |
| `withEmbeddingSpan(...)` | `Terra.embed(...).run { ... }` |
| `withSafetyCheckSpan(...)` | `Terra.safety(...).run { ... }` |
| `.execute { ... }` | `.run { ... }` |
| `.attribute(...)` | `.attr(...)` |
| `.includeContent()` | `.capture(.includeContent)` |
| `Terra.inference(...)` | `Terra.infer(...)` |
| `Terra.embedding(...)` | `Terra.embed(...)` |
| `Terra.safetyCheck(...)` | `Terra.safety(...)` |

## Startup Migration

### Before

```swift
try Terra.enable(.quickstart)
```

### After

```swift
try Terra.start()
```

## Inference Call Migration

### Before

```swift
let answer = try await Terra.inference(model: "gpt-4o-mini", prompt: prompt) {
  try await llm.generate(prompt)
}
```

### After

```swift
let answer = try await Terra.infer("gpt-4o-mini", prompt: prompt).run {
  try await llm.generate(prompt)
}
```

## Builder/Metadata Migration

### Before

```swift
let answer = try await Terra
  .inference(model: "gpt-4o-mini", prompt: prompt)
  .attribute(.init("app.user_tier"), "pro")
  .includeContent()
  .execute {
    try await llm.generate(prompt)
  }
```

### After

```swift
let answer = try await Terra
  .infer("gpt-4o-mini", prompt: prompt)
  .attr(.init("app.user_tier"), "pro")
  .capture(.includeContent)
  .run {
    try await llm.generate(prompt)
  }
```

## Privacy Migration

Use `Terra.PrivacyPolicy` in `Terra.Configuration`:

```swift
var config = Terra.Configuration()
config.privacy = .redacted
try Terra.start(config)
```

## Recommended Migration Order

1. Move startup calls to `Terra.start(...)`.
2. Replace operation names (`inference` -> `infer`, `embedding` -> `embed`, `safetyCheck` -> `safety`).
3. Replace terminals/modifiers (`execute` -> `run`, `attribute` -> `attr`, `includeContent` -> `capture(.includeContent)`).
4. Validate traces in your OTLP backend after rollout.
