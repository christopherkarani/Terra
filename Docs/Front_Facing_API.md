# Terra Front-Facing API (Current)

This document lists the canonical public API for SDK consumers.

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
- `.run { ... }`
- `.run { trace in ... }`

### Trace handle (`Terra.TraceHandle`)

- `.event(_:)`
- `.attr(_:_:)`
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
- `Terra.Call`

### Typed identifiers

- `Terra.ModelID`
- `Terra.ProviderID`
- `Terra.RuntimeID`
- `Terra.ToolCallID`

### Error model

- `Terra.TerraError`
- `Terra.TerraError.Code` (`invalid_endpoint`, `persistence_setup_failed`, `already_started`, `invalid_lifecycle_state`, ...)

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

## Legacy Notes

The following names are legacy and are not the canonical front-facing API:

- `Terra.inference`, `Terra.embedding`, `Terra.safetyCheck`
- `InferenceCall`, `StreamingCall`, `EmbeddingCall`, `AgentCall`, `ToolCall`, `SafetyCheckCall`
- `.execute`, `.attribute`, `.attributes`, `.includeContent`
