# Terra Front-Facing API Examples

Copy-paste examples covering the public Terra API surface.

## 1) Quickstart and Presets

```swift
import Terra

// Quickstart
try Terra.start()

// Production preset (persistence enabled)
try Terra.start(.init(preset: .production))

// Diagnostics preset
try Terra.start(.init(preset: .diagnostics))
```

## 2) Custom `Terra.Configuration`

```swift
import Terra

var config = Terra.Configuration()
config.privacy = .redacted
config.endpoint = URL(string: "http://127.0.0.1:4318")!
config.serviceName = "com.example.app"
config.serviceVersion = "3.0.0"
config.samplingRatio = 1.0
config.enableLogs = true
config.instrumentations = [.coreML, .httpAIAPIs, .openClawGateway]
config.openClaw = .init(mode: .gatewayOnly, gatewayHosts: ["localhost", "127.0.0.1"])
config.profiling = .init(enableMemoryProfiler: true, enableMetalProfiler: true)

try Terra.start(config)
```

## 3) Closure-First Inference

```swift
import Terra

let response = try await Terra.inference(
  model: "gpt-4o-mini",
  prompt: "Summarize the release notes",
  provider: "openai",
  runtime: "http_api",
  temperature: 0.2,
  maxOutputTokens: 300
) { trace in
  trace.event("request.start")

  // Replace with your SDK/client call.
  let output = "Summary text"

  trace.tokens(input: 120, output: 70)
  trace.responseModel("gpt-4o-mini")
  return output
}
```

## 4) Streaming Inference (TTFT and token progress)

```swift
import Terra

let finalText = try await Terra.stream(
  model: "gpt-4o-mini",
  prompt: "Stream a short response",
  provider: "openai",
  runtime: "http_api"
) { trace in
  trace.firstToken()
  trace.chunk(tokens: 5)
  trace.chunk(tokens: 7)
  trace.outputTokens(12)
  return "Done"
}
```

## 5) Agent, Tool, Embedding, Safety

```swift
import Terra

let plan = try await Terra.agent(name: "planner", id: "agent-42") { _ in
  let docs = try await Terra.tool(
    name: "web_search",
    callID: UUID().uuidString,
    type: "function"
  ) { _ in
    "search results"
  }

  let embedding = try await Terra.embedding(
    model: "text-embedding-3-small",
    inputCount: 1,
    provider: "openai",
    runtime: "http_api"
  ) { _ in
    [[0.11, 0.22, 0.33]]
  }

  let safe = await Terra.safetyCheck(name: "toxicity", subject: docs) { _ in true }
  return "safe=\(safe), vectors=\(embedding.count)"
}

_ = plan
```

## 6) Builder API

```swift
import Terra

let result = try await Terra
  .inference(model: "gpt-4o-mini", prompt: "Hello")
  .provider("openai")
  .runtime("http_api")
  .temperature(0.3)
  .maxOutputTokens(200)
  .includeContent()
  .attribute(.init("app.request_id"), UUID().uuidString)
  .attributes { bag in
    bag.set(.init("app.user_tier"), "pro")
    bag.set(.init("app.retry"), false)
  }
  .execute { trace in
    trace.event("builder.path")
    return "ok"
  }

_ = result
```

## 7) Session-Scoped Calls

```swift
import Terra

let session = Terra.Session()

let answer = try await session
  .inference(model: "gpt-4o-mini", prompt: "Session question")
  .provider("openai")
  .execute { trace in
    trace.event("session.inference")
    return "session answer"
  }

_ = answer
```

## 8) Custom Terra Events

```swift
import Terra

struct GuardrailEvent: Terra.TerraEvent {
  static var name: StaticString { "guardrail.decision" }
  let policy: String
  let blocked: Bool

  func encode(into attributes: inout Terra.AttributeBag) {
    attributes.set(.init("guardrail.policy"), policy)
    attributes.set(.init("guardrail.blocked"), blocked)
  }
}

_ = try await Terra.inference(model: "gpt-4o-mini", prompt: "Test") { trace in
  trace.emit(GuardrailEvent(policy: "toxicity", blocked: false))
  return "ok"
}
```

## 9) `TerraTraceable` Return Type

```swift
import Terra

struct Reply: Terra.TerraTraceable {
  let text: String
  var terraTokenUsage: Terra.TokenUsage? { .init(input: 11, output: 7) }
  var terraResponseModel: String? { "gpt-4o-mini" }
}

_ = try await Terra.inference(model: "gpt-4o-mini", prompt: "Hi") {
  Reply(text: "Hello")
}
```

## 10) `@Traced` Macro (`TerraTracedMacro`)

```swift
import TerraTracedMacro

@Traced(model: "gpt-4o-mini", provider: "openai")
func generate(prompt: String) async throws -> String {
  "response: \(prompt)"
}

@Traced(agent: "planner")
func planner() async throws -> String { "done" }

@Traced(tool: "search", type: "function")
func search(query: String) async throws -> String { "results" }

@Traced(embedding: "text-embedding-3-small", inputCount: 1)
func embed(text: String) async throws -> [Float] { [0.1, 0.2] }

@Traced(safety: "toxicity")
func moderate(subject: String) async throws -> Bool { true }
```

## 11) Foundation Models (`TerraFoundationModels`)

```swift
#if canImport(FoundationModels)
import FoundationModels
import TerraFoundationModels

@available(macOS 26.0, iOS 26.0, *)
func runFoundationModels() async throws {
  let session = Terra.TracedSession(model: .default, instructions: "Be concise")

  let text = try await session.respond(to: "Say hello")
  print(text)

  struct Plan: Generable { let steps: [String] }
  let typed = try await session.respond(to: "Give me three steps", generating: Plan.self)
  print(typed.steps)

  for try await chunk in session.streamResponse(to: "Stream this answer") {
    print(chunk, terminator: "")
  }
}
#endif
```

## 12) MLX (`TerraMLX`)

```swift
import TerraMLX

let text = try await TerraMLX.traced(
  model: "mlx-community/Llama-3.2-1B",
  maxTokens: 256,
  temperature: 0.7,
  device: "ane",
  memoryFootprintMB: 512,
  modelLoadDurationMS: 1800
) {
  TerraMLX.recordFirstToken()
  TerraMLX.recordTokenCount(32)
  return "mlx output"
}

_ = text
```

## 13) Llama (`TerraLlama`)

```swift
import TerraLlama

let output = try await TerraLlama.traced(model: "llama-3.2", prompt: "Hello") { trace in
  trace.chunk(tokens: 1)
  TerraLlama.applyDecodeStats(
    .init(tokensPerSecond: 40, timeToFirstTokenMS: 95, kvCacheUsagePercent: 62),
    to: trace
  )
  TerraLlama.recordLayerMetrics(
    [.init(layerName: "layer_0_attn", durationMS: 1.7, memoryMB: 5.1)],
    to: trace
  )
  return "llama output"
}

_ = output
```

## 14) Core ML (`TerraCoreML`)

```swift
#if canImport(CoreML)
import CoreML
import TerraCoreML

CoreMLInstrumentation.install(.init(excludedModels: ["tiny-fast-model"]))

let attrs = TerraCoreML.attributes(computeUnits: .all)
print(attrs)
#endif
```

## 15) HTTP Auto-Instrumentation (`TerraHTTPInstrument`)

```swift
import TerraHTTPInstrument

HTTPAIInstrumentation.install(
  hosts: ["api.openai.com", "api.anthropic.com"],
  openClawGatewayHosts: ["localhost", "127.0.0.1"],
  openClawMode: "gateway_only"
)
```

## 16) Profilers (`TerraSystemProfiler`, `TerraMetalProfiler`, `TerraAccelerate`)

```swift
import TerraSystemProfiler
import TerraMetalProfiler
import TerraAccelerate

TerraSystemProfiler.installMemoryProfiler()
let start = TerraSystemProfiler.captureMemorySnapshot()
// ... work ...
let end = TerraSystemProfiler.captureMemorySnapshot()
let memDelta = TerraSystemProfiler.memoryDeltaAttributes(start: start, end: end)
print(memDelta)

TerraMetalProfiler.install()
let metal = TerraMetalProfiler.attributes(gpuUtilization: 0.72, memoryInFlightMB: 96, computeTimeMS: 11.4)
print(metal)

let accel = TerraAccelerate.attributes(backend: "BNNS", operation: "matmul", durationMS: 1.1)
print(accel)

let threads = ThreadProfiler.capture()
print("threads:", threads.threadCountEstimate)
print(NeuralEngineResearch.probeSummary())
```

## 17) TraceKit (`TerraTraceKit`)

```swift
import TerraTraceKit

// Load persisted traces
let loader = TraceLoader()
let loadResult = try loader.loadTracesWithFailures(maxFiles: 200)
print("loaded:", loadResult.traces.count, "failures:", loadResult.failures.count)

// Render
if let first = loadResult.traces.first {
  let timeline = TimelineViewModel(trace: first)
  print("lanes:", timeline.lanes.count)
}

// In-process OTLP server + store
let store = TraceStore(maxSpans: 50_000)
let server = OTLPHTTPServer(host: "127.0.0.1", port: 4318, traceStore: store)
try server.start()

let snapshot = await store.snapshot(filter: .init(namePrefix: "gen_ai."))
let tree = TreeRenderer().render(snapshot: snapshot)
let stream = StreamRenderer().render(spans: snapshot.allSpans)

print(tree)
print(stream.joined(separator: "\n"))
server.stop()
```

## 18) Graceful Shutdown

```swift
import Terra

await Terra.shutdown()
```
