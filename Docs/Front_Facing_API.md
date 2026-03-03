# Terra Front-Facing API (v3)

This document lists the public developer API exported by Terra package products.

## Package Products

- `Terra` (umbrella: TerraCore + auto-instrumentation start API)
- `TerraCore` (core tracing API)
- `TerraTracedMacro` (`@Traced` macro surface)
- `TerraFoundationModels`
- `TerraMLX`
- `TerraLlama`
- `TerraCoreML`
- `TerraHTTPInstrument`
- `TerraTraceKit`
- `TerraMetalProfiler`
- `TerraSystemProfiler`
- `TerraAccelerate`

## 1) `import Terra`

### Lifecycle and install

- `Terra.start(_ config: Terra.Configuration = .init()) throws`
- `Terra.install(_ installation: Terra.Installation)`
- `Terra.installOpenTelemetry(_ configuration: Terra.OpenTelemetryConfiguration) throws`
- `Terra.shutdown() async`
- `Terra.lifecycleState: Terra.LifecycleState`
- `Terra.isRunning: Bool`
- `Terra.defaultPersistenceStorageURL() -> URL`

### Canonical operation API (closure-first)

- `Terra.inference(...) async rethrows -> R`
- `Terra.stream(...) async rethrows -> R`
- `Terra.embedding(...) async rethrows -> R`
- `Terra.agent(...) async rethrows -> R`
- `Terra.tool(...) async rethrows -> R`
- `Terra.safetyCheck(...) async rethrows -> R`

Each operation has:
- one overload with `() async throws -> R`
- one overload with typed trace handle `(TraceType) async throws -> R`

### Builder factories

- `Terra.inference(...) -> Terra.InferenceCall`
- `Terra.stream(...) -> Terra.StreamingCall`
- `Terra.embedding(...) -> Terra.EmbeddingCall`
- `Terra.agent(...) -> Terra.AgentCall`
- `Terra.tool(...) -> Terra.ToolCall`
- `Terra.safetyCheck(...) -> Terra.SafetyCheckCall`

### Builder methods

Shared methods on all builders:
- `.includeContent()`
- `.attribute(_:_:)`
- `.attributes { ... }`
- `.execute { ... }`

Builder-specific methods:

- `InferenceCall`
  - `.runtime(_:)`
  - `.provider(_:)`
  - `.responseModel(_:)`
  - `.tokens(input:output:)`
  - `.temperature(_:)`
  - `.maxOutputTokens(_:)`
- `StreamingCall`
  - `.runtime(_:)`
  - `.provider(_:)`
  - `.temperature(_:)`
  - `.maxOutputTokens(_:)`
  - `.expectedOutputTokens(_:)`
- `EmbeddingCall`
  - `.runtime(_:)`
  - `.provider(_:)`
- `AgentCall`
  - `.runtime(_:)`
  - `.provider(_:)`
- `ToolCall`
  - `.runtime(_:)`
  - `.provider(_:)`
- `SafetyCheckCall`
  - `.runtime(_:)`
  - `.provider(_:)`

### Session-scoped API

- `Terra.Session` (actor)
  - `init()`
  - `inference(...)`
  - `stream(...)`
  - `embedding(...)`
  - `agent(...)`
  - `tool(...)`
  - `safetyCheck(...)`

### Trace handles

- `Terra.InferenceTrace`
- `Terra.StreamingTrace`
- `Terra.EmbeddingTrace`
- `Terra.AgentTrace`
- `Terra.ToolTrace`
- `Terra.SafetyCheckTrace`

Common trace methods:
- `.event(_:)`
- `.attribute(_:_:)`
- `.emit(_:)`
- `.recordError(_:)`

Specialized:
- `InferenceTrace`: `.tokens(input:output:)`, `.responseModel(_:)`
- `StreamingTrace`: `.chunk(tokens:)`, `.outputTokens(_:)`, `.firstToken()`

### Request types

- `Terra.InferenceRequest`
- `Terra.StreamingRequest`
- `Terra.EmbeddingRequest`
- `Terra.AgentRequest`
- `Terra.ToolRequest`
- `Terra.SafetyCheckRequest`

### Privacy and capture controls

- `Terra.PrivacyPolicy` (v3 high-level)
  - `.redacted`, `.lengthOnly`, `.capturing`, `.silent`
- `Terra.Privacy` (low-level)
- `Terra.ContentPolicy`
- `Terra.CaptureIntent`
- `Terra.RedactionStrategy`

### Typed telemetry/event API

- `Terra.TelemetryAttributeValue`
- `Terra.TelemetryValue`
- `Terra.AttributeKey<Value>`
- `Terra.AttributeBag`
- `Terra.TerraEvent`

### Traceable return model API

- `Terra.TerraTraceable`
  - `terraTokenUsage`
  - `terraResponseModel`
- `Terra.TokenUsage`

### Key namespaces

- `Terra.Key.*` (typed keys)
- `Terra.Keys.GenAI.*` (string key constants)
- `Terra.Keys.Terra.*` (string key constants)

### Start configuration (`Terra` umbrella)

- `Terra.Configuration`
  - presets: `.quickstart`, `.production`, `.diagnostics`
- `Terra.Instrumentations` (`OptionSet`)
  - `.coreML`, `.httpAIAPIs`, `.openClawGateway`, `.openClawDiagnostics`, `.all`, `.none`
- `Terra.Profiling`
- `Terra.OpenClawConfiguration`
- `Terra.ProxyConfiguration`

## 2) `import TerraTracedMacro`

Attached body macros:

- `@Traced(model:prompt:provider:temperature:maxTokens:maxOutputTokens:streaming:)`
- `@Traced(agent:id:)`
- `@Traced(tool:callID:type:)`
- `@Traced(embedding:count:inputCount:)`
- `@Traced(safety:subject:)`

## 3) `import TerraFoundationModels`

Availability: `@available(macOS 26.0, iOS 26.0, *)`

- `TerraTracedSession`
  - `init(model:instructions:modelIdentifier:)`
  - `modelIdentifier`
  - `respond(to:promptCapture:) async throws -> String`
  - `respond(to:generating:promptCapture:) async throws -> T`
  - `streamResponse(to:promptCapture:) -> AsyncThrowingStream<String, Error>`
- `Terra.TracedSession` (typealias convenience)

## 4) `import TerraMLX`

- `TerraMLX.traced(...) async throws -> R`
- `TerraMLX.recordFirstToken()`
- `TerraMLX.recordTokenCount(_:)`
- `Terra.MLX` (alias, when importing umbrella `Terra`)

## 5) `import TerraLlama`

- `TerraLlama.DecodeStats`
- `TerraLlama.LayerMetric`
- `TerraLlama.traced(model:prompt:_:)`
- `TerraLlama.applyDecodeStats(_:to:)`
- `TerraLlama.recordLayerMetrics(_:to:)`

## 6) `import TerraCoreML`

- `TerraCoreML.Keys`
- `TerraCoreML.attributes(computeUnits:)`
- `TerraCoreML.attributes(configuration:)`
- `Terra.InferenceTrace.coreML(computeUnits:)`
- `Terra.InferenceTrace.coreML(configuration:)`
- `CoreMLInstrumentation.Configuration`
- `CoreMLInstrumentation.install(_:)`

## 7) `import TerraHTTPInstrument`

- `HTTPAIInstrumentation.defaultAIHosts`
- `HTTPAIInstrumentation.defaultOpenClawGatewayHosts`
- `HTTPAIInstrumentation.install(hosts:openClawGatewayHosts:openClawMode:)`

## 8) `import TerraTraceKit`

### Data model

- `TraceID`, `SpanID`, `SpanKind`, `StatusCode`
- `AttributeValue`, `Attribute`, `Attributes`, `Resource`
- `SpanRecord`, `TraceFilter`, `TraceSnapshot`

### Ingestion and decoding

- `OTLPRequestDecoder`
- `OTLPRequestDecoder.Limits`
- `OTLPRequestDecoderError`
- `OTLPHTTPServer`
- `OTLPHTTPServer.Limits`

### Persistence and loading

- `TraceFileLocator`
- `TraceFileReference`
- `TraceFileReader`
- `TraceFileError`
- `TraceDecoder`
- `TraceDecodingError`
- `TraceLoader`
- `TraceLoadResult`
- `TraceStore`

### Rendering and VM helpers

- `StreamRenderer`
- `TreeRenderer`
- `Trace`
- `TraceModelError`
- `TraceListViewModel`
- `TimelineViewModel`
- `SpanTimelineItem`
- `TimelineLane`
- `SpanDetailViewModel`
- `AttributeItem`
- `EventItem`
- `LinkItem`
- `TerraTelemetryClassifier`

## 9) `import TerraMetalProfiler`

- `TerraMetalProfiler.install()`
- `TerraMetalProfiler.isInstalled`
- `TerraMetalProfiler.attributes(gpuUtilization:memoryInFlightMB:computeTimeMS:)`

## 10) `import TerraSystemProfiler`

- `TerraSystemProfiler.MemorySnapshot`
- `TerraSystemProfiler.installMemoryProfiler()`
- `TerraSystemProfiler.isMemoryProfilerEnabled`
- `TerraSystemProfiler.captureMemorySnapshot()`
- `TerraSystemProfiler.memoryDeltaAttributes(start:end:)`
- `ThreadProfiler.capture()`
- `NeuralEngineResearch.isExperimentalProbeEnabled`
- `NeuralEngineResearch.probeSummary()`

## 11) `import TerraAccelerate`

- `TerraAccelerate.attributes(backend:operation:durationMS:)`

## Deprecated but still public (compatibility)

- Builder `.run { ... }` methods (use `.execute { ... }`)
- Builder `.capture(_:)` methods (use `.includeContent()`)
- `Terra.shared()` (prefer closure-first or `Terra.Session`)
- Legacy key aliases:
  - `Terra.Key.requestModel`
  - `Terra.Key.requestMaxTokens`
  - `Terra.Key.requestTemperature`
  - `Terra.Keys.GenAI.model`
