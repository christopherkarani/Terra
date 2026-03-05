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
- `.responseModel(_:)`
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

- `@Traced(model:prompt:provider:temperature:maxTokens:maxOutputTokens:streaming:)`
- `@Traced(agent:id:)`
- `@Traced(tool:callID:type:)`
- `@Traced(embedding:count:inputCount:)`
- `@Traced(safety:subject:)`

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
