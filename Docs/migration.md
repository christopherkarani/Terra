# Terra Migration Guide (Legacy -> Current)

This guide migrates existing integrations to the canonical composable API:

- Startup: `Terra.start(...)` (`async`)
- Operations: `Terra.infer/stream/embed/agent/tool/safety`
- Terminal: `.run { ... }`
- Metadata: `.attr(...)` / `.metadata { ... }`
- Per-call content capture: `.capture(.includeContent)`
- Stable lifecycle errors: `Terra.TerraError` (`code`-based)
- Typed identifiers: `Terra.ModelID`, `Terra.ProviderID`, `Terra.RuntimeID`, `Terra.ToolCallID`

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
try await Terra.start()
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
let answer = try await Terra
  .infer(
    Terra.ModelID("gpt-4o-mini"),
    prompt: prompt,
    provider: Terra.ProviderID("openai"),
    runtime: Terra.RuntimeID("http_api")
  )
  .run {
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
  .infer(Terra.ModelID("gpt-4o-mini"), prompt: prompt)
  .capture(.includeContent)
  .run { trace in
    // Use trace.tag() for attributes within the run closure
    trace.tag("app.user_tier", "pro")
    trace.event("request.start")
    return try await llm.generate(prompt)
  }
```

## Lifecycle Error Migration

Lifecycle/configuration throws now surface as `Terra.TerraError` with stable `code` values:

- `invalid_endpoint`
- `persistence_setup_failed`
- `already_started`
- `invalid_lifecycle_state`

Example assertion:

```swift
do {
  try await Terra.start(config)
} catch let error as Terra.TerraError {
  guard error.code == .invalid_endpoint else { throw error }
}
```

## Privacy Migration

Use `Terra.PrivacyPolicy` in `Terra.Configuration`:

```swift
var config = Terra.Configuration()
config.privacy = .redacted
try await Terra.start(config)
```

## Recommended Migration Order

1. Move startup calls to `Terra.start(...)`.
2. Replace operation names (`inference` -> `infer`, `embedding` -> `embed`, `safetyCheck` -> `safety`).
3. Replace terminals/modifiers (`execute` -> `run`, `attribute` -> `attr`, `includeContent` -> `capture(.includeContent)`).
4. Validate traces in your OTLP backend after rollout.
