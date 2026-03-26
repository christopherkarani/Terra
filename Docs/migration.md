# Terra Migration Guide (Legacy -> Current)

This guide migrates existing integrations to the canonical composable API:

- Startup: `Terra.start(...)` (`async`)
- Operations: `Terra.infer/stream/embed/agent/tool/safety`
- Agent loops: `Terra.agentic(name:id:_:)`
- Terminal: `.run { ... }`
- Metadata: `trace.tag(...)` for `TraceHandle`, or `span.attribute(...)` when you are using `SpanHandle`
- Per-call content capture: `.capture(.includeContent)`
- Stable lifecycle errors: `Terra.TerraError` (`code`-based)
- Structured chat prompts: `Terra.infer(..., messages: [Terra.ChatMessage])`
- Typed identifiers: `Terra.ProviderID`, `Terra.RuntimeID`; `Terra.ModelID` and `Terra.ToolCallID` remain as compatibility wrappers for older call sites

## API Mapping

| Legacy API | Current replacement |
| --- | --- |
| `withInferenceSpan(...)` | `Terra.infer(...).run { ... }` |
| `withStreamingInferenceSpan(...)` | `Terra.stream(...).run { trace in ... }` |
| `withAgentInvocationSpan(...)` | `Terra.agent(...).run { ... }` |
| `withToolExecutionSpan(...)` | `Terra.tool(...).run { ... }` |
| `withEmbeddingSpan(...)` | `Terra.embed(...).run { ... }` |
| `withSafetyCheckSpan(...)` | `Terra.safety(...).run { ... }` |
| multi-step planner / tool loop | `Terra.agentic(name:id:_:) { agent in ... }` |
| raw `Task.detached` with tracing assumptions | `SpanHandle.detached(...)` or `AgentHandle.detached(...)` |
| `.execute { ... }` | `.run { ... }` |
| `.attribute(...)` | `trace.tag(...)` |
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
    "gpt-4o-mini",
    prompt: prompt,
    provider: Terra.ProviderID("openai"),
    runtime: Terra.RuntimeID("http_api")
  )
  .run {
    try await llm.generate(prompt)
  }
```

## Structured Prompt Migration

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
    "gpt-4o-mini",
    messages: [
      .init(role: "system", content: "You are a precise assistant."),
      .init(role: "user", content: prompt)
    ]
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
  .infer("gpt-4o-mini", prompt: prompt)
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
- `wrong_api_for_agentic`
- `context_not_propagated`

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
3. Move multi-step agent loops to `Terra.agentic(...)` and replace raw `Task.detached` trace assumptions with Terra's detached helpers. Detached work launched after a parent span ends now degrades to a warning event instead of throwing.
4. Replace terminals/modifiers (`execute` -> `run`, `attribute` -> `tag` for `TraceHandle`, `includeContent` -> `capture(.includeContent)`).
5. Validate traces in your OTLP backend after rollout.
