# Terra Front-Facing API (Current)

This document lists the canonical public API for SDK consumers.

## 0) 90-second quickstart + copy-ready recipes

These snippets compile without edits from `Examples/Terra Sample/RecipeSnippets.swift`.

### 90-second path

```swift
static func ninetySecondPath(prompt: String = "Give me a short release summary.") async throws -> String {
  try await Terra.start(.init(preset: .quickstart))
  let answer = try await inferRecipe(prompt: prompt)
  await Terra.shutdown()
  return answer
}
```

### Infer recipe

```swift
static func inferRecipe(prompt: String) async throws -> String {
  try await Terra
    .infer(
      Terra.ModelID("gpt-4o-mini"),
      prompt: prompt,
      provider: Terra.ProviderID("openai"),
      runtime: Terra.RuntimeID("http_api")
    )
    .metadata {
      Terra.event("infer.request")
      Terra.attr(sampleKindKey, "infer")
    }
    .run { trace in
      trace.attr(userTierKey, "free")
      trace.tokens(input: 42, output: 18)
      return "stubbed-infer-response"
    }
}
```

### Tool recipe

```swift
static func toolRecipe(query: String) async throws -> [String] {
  try await Terra
    .tool(
      "search",
      callID: Terra.ToolCallID("tool-call-1"),
      type: "web_search",
      provider: Terra.ProviderID("openai"),
      runtime: Terra.RuntimeID("http_api")
    )
    .metadata {
      Terra.event("tool.invoked")
      Terra.attr(sampleKindKey, "tool")
    }
    .attr(queryLengthKey, query.count)
    .run { _ in
      ["result for \(query)"]
    }
}
```

### Agent recipe

```swift
static func agentRecipe(task: String) async throws -> String {
  try await Terra
    .agent(
      "planner",
      id: "agent-1",
      provider: Terra.ProviderID("openai"),
      runtime: Terra.RuntimeID("http_api")
    )
    .metadata {
      Terra.event("agent.begin")
      Terra.attr(sampleKindKey, "agent")
    }
    .run { trace in
      trace.attr(taskKey, task)
      _ = try await toolRecipe(query: task)
      return try await inferRecipe(prompt: "Plan next steps for: \(task)")
    }
}
```

## 1) `import Terra`

### Startup

- `Terra.start(_ config: Terra.Configuration = .init()) async throws`
- `Terra.lifecycleState`
- `Terra.isRunning`
- `Terra.shutdown() async`
- `Terra.reset() async`
- `Terra.reconfigure(_ config: Terra.Configuration) async throws`
- `Terra.TerraError`

### Canonical operation factories

- `Terra.infer(_:prompt:provider:runtime:temperature:maxTokens:) -> Terra.Call`
- `Terra.stream(_:prompt:provider:runtime:temperature:maxTokens:expectedTokens:) -> Terra.Call`
- `Terra.embed(_:inputCount:provider:runtime:) -> Terra.Call`
- `Terra.agent(_:id:provider:runtime:) -> Terra.Call`
- `Terra.tool(_:callID:type:provider:runtime:) -> Terra.Call`
- `Terra.safety(_:subject:provider:runtime:) -> Terra.Call`

### Shared call composition (`Terra.Call`)

- `.capture(_ policy: Terra.CapturePolicy)`
- `.attr(_ key: Terra.TraceKey<Value>, _ value: Value) where Value: Terra.ScalarValue`
- `.metadata { ... }` (`@Terra.MetadataBuilder`)
- `.run { ... }`
- `.run { trace in ... }`

### Trace handle (`Terra.TraceHandle`)

- `.event(_:)`
- `.attr(_:_:)`
- `.metadata { ... }` (`@Terra.MetadataBuilder`)
- `.tokens(input:output:)`
- `.responseModel(_ value: Terra.ModelID)`
- `.chunk(_:)`
- `.outputTokens(_:)`
- `.firstToken()`
- `.recordError(_:)`

### Scalar/key model

- `Terra.ScalarValue`
- `Terra.TraceScalar`
- `Terra.TraceKey<Value>`
- `Terra.TraceAttribute`
- `Terra.Metadata`
- `Terra.MetadataBuilder`
- `Terra.event(_:)`
- `Terra.attr(_:_:)`
- `Terra.Call`
- `Terra.CallDescriptor`

### Typed identifiers

- `Terra.ModelID`
- `Terra.ProviderID`
- `Terra.RuntimeID`
- `Terra.ToolCallID`

### Injection seams

- `Terra.ProviderSeam`
- `Terra.ExecutorSeam`
- `Terra.RuntimeSeam`

### Error model

- `Terra.TerraError`
- `Terra.TerraError.remediationHint`
- `Terra.TerraError.Code` (`invalid_endpoint`, `persistence_setup_failed`, `already_started`, `invalid_lifecycle_state`, ...)

#### Deterministic lifecycle error mapping (`code -> cause -> action`)

| `TerraError.code` | Deterministic cause | Remediation action |
| --- | --- | --- |
| `invalid_endpoint` | `Terra.start`/`Terra.reconfigure` received an invalid OTLP endpoint URL. | Use a valid OTLP endpoint URL (`http/https` + host), then retry start/reconfigure. |
| `persistence_setup_failed` | Persistence storage could not be created/opened/written. | Ensure `persistence.storageURL` points to a writable directory, then retry start/reconfigure. |
| `already_started` | `Terra.start` was called while already running with incompatible state/config. | Use `Terra.reconfigure(...)` for live updates, or call `Terra.shutdown()/reset()` before starting again. |
| `invalid_lifecycle_state` | Lifecycle API was called from an invalid state transition. | Call lifecycle APIs only from valid states (for example: `start` before `reconfigure`/`shutdown`). |
| `start_failed` | Startup failed after entering lifecycle start path. | Inspect `TerraError.context` and `TerraError.underlying`, fix config/runtime issues, then retry `Terra.start()`. |
| `reconfigure_failed` | Reconfigure failed while applying a runtime config change. | Inspect `TerraError.context` and `TerraError.underlying`, fix config delta issues, then retry `Terra.reconfigure(...)`. |

### Privacy

- `Terra.PrivacyPolicy`
- `Terra.CapturePolicy`

### Start configuration

- `Terra.Configuration`
- `Terra.Configuration.Preset` (`quickstart`, `production`, `diagnostics`)
- `Terra.Configuration.Persistence`
- `Terra.Configuration.Persistence.Performance`
- `Terra.Profiling`
- `Terra.Instrumentations`
- `Terra.OpenClawConfiguration`
- `Terra.ProxyConfiguration`

## 2) `import TerraTracedMacro`

Attached body macros:

- `@Traced(model:prompt:provider:runtime:temperature:maxTokens:maxOutputTokens:streaming:)`
- `@Traced(agent:id:runtime:)`
- `@Traced(tool:callID:type:runtime:)`
- `@Traced(embedding:count:inputCount:runtime:)`
- `@Traced(safety:subject:runtime:)`

## 3) Integrations

- `TerraFoundationModels` (`Terra.TracedSession`)
- `TerraMLX` (`TerraMLX.traced(...)`)
- `TerraLlama` (`TerraLlama.traced(...)`)
- `TerraCoreML`, `TerraHTTPInstrument`, `TerraTraceKit`, `TerraMetalProfiler`, `TerraSystemProfiler`
