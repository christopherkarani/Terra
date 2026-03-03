# Terra Migration Guide (v1 → v2 → v3)

This guide moves existing Terra integrations onto the v3 canonical API:

- Start with `Terra.start()` or `Terra.start(.init(...))`
- Prefer closure-first factories (`Terra.inference { ... }`)
- Use builder `.execute { ... }` only when you need dynamic metadata

## v1 → v3 Mapping

| v1 API | v3 replacement |
| --- | --- |
| `withInferenceSpan(...)` | `try await Terra.inference(model:prompt:) { ... }` |
| `withStreamingInferenceSpan(...)` | `try await Terra.stream(model:prompt:) { trace in ... }` |
| `withAgentInvocationSpan(...)` | `try await Terra.agent(name:id:) { ... }` |
| `withToolExecutionSpan(...)` | `try await Terra.tool(name:callID:type:) { ... }` |
| `withEmbeddingSpan(...)` | `try await Terra.embedding(model:inputCount:) { ... }` |
| `withSafetyCheckSpan(...)` | `try await Terra.safetyCheck(name:subject:) { ... }` |

## v2 → v3 Mapping

| v2 API | v3 replacement |
| --- | --- |
| `.run { ... }` | `.execute { ... }` |
| `.capture(.optIn)` | `.includeContent()` |
| `Terra.enable(...)` | `Terra.start(...)` |
| `Terra.configure(...)` | `Terra.start(...)` with `Terra.Configuration` |
| `AutoInstrumentConfiguration` | `Terra.Configuration` |
| `StartProfile` | `Terra.Configuration.Preset` |

## Setup Migration

### Before (v1/v2)

```swift
try Terra.enable(.quickstart)
```

### After (v3)

```swift
try Terra.start()
```

### Before (preset setup)

```swift
try Terra.start(.production) { config in
  config.enableLogs = true
}
```

### After (preset setup)

```swift
var config = Terra.Configuration(preset: .production)
config.enableLogs = true
try Terra.start(config)
```

## Privacy Migration

v3 consolidates privacy selection into `Terra.PrivacyPolicy`.

| Previous concepts | v3 |
| --- | --- |
| `ContentPolicy` + `CaptureIntent` + `RedactionStrategy` composition | `Terra.PrivacyPolicy` |
| Separate policy + redaction setup in multiple places | One policy in `Terra.Configuration.privacy` |

### Before

```swift
var config = Terra.Configuration()
config.privacy.contentPolicy = .optIn
config.privacy.redaction = .hashSHA256
try Terra.start(config)
```

### After

```swift
var config = Terra.Configuration()
config.privacy = .capturing
try Terra.start(config)
```

## Builder Terminal + Capture Migration

### Before

```swift
let answer = try await Terra
  .inference(model: "gpt-4o-mini", prompt: prompt)
  .capture(.optIn)
  .run {
    try await llm.generate(prompt)
  }
```

### After

```swift
let answer = try await Terra
  .inference(model: "gpt-4o-mini", prompt: prompt)
  .includeContent()
  .execute {
    try await llm.generate(prompt)
  }
```

## Closure-First Migration

### Before (builder-only style)

```swift
let answer = try await Terra
  .inference(model: "gpt-4o-mini", prompt: prompt)
  .execute {
    try await llm.generate(prompt)
  }
```

### After (recommended)

```swift
let answer = try await Terra.inference(model: "gpt-4o-mini", prompt: prompt) {
  try await llm.generate(prompt)
}
```

## Deprecation Timeline

| API family | Status in v3 | Removal target |
| --- | --- | --- |
| v1 span wrappers | Deprecated compatibility path | Next major after deprecation window |
| v2 `.run` / `.capture` shims | Deprecated with forwarding | Next major after deprecation window |
| `AutoInstrumentConfiguration` / `StartProfile` | Deprecated aliases/bridges | Next major after migration window |
| `Terra.enable` / `Terra.configure` / legacy `bootstrap` | Deprecated forwarding APIs | Next major after migration window |

## Recommended Migration Order

1. Move startup calls to `Terra.start(...)`.
2. Replace `.run` with `.execute` and `.capture(.optIn)` with `.includeContent()`.
3. Convert high-volume call sites to closure-first factories.
4. Collapse legacy privacy wiring into `Terra.PrivacyPolicy`.
5. Enable `@Traced` macros where function-level instrumentation is cleaner.
