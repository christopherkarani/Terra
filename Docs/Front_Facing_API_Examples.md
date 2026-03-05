# Terra Front-Facing API Examples

Copy-paste examples for the canonical public API.

## 1) Quickstart and Presets

```swift
import Terra

try await Terra.start()
try await Terra.start(.init(preset: .production))
try await Terra.start(.init(preset: .diagnostics))
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
config.persistence = .defaults()

try await Terra.start(config)
```

## 3) Inference

```swift
import Terra

let response = try await Terra
  .infer(
    "gpt-4o-mini",
    prompt: "Summarize the release notes",
    provider: "openai",
    runtime: "http_api",
    temperature: 0.2,
    maxTokens: 300
  )
  .run { trace in
    trace.event("request.start")
    trace.tokens(input: 120, output: 70)
    trace.responseModel("gpt-4o-mini")
    return "Summary text"
  }
```

## 4) Streaming

```swift
import Terra

let finalText = try await Terra
  .stream("gpt-4o-mini", prompt: "Stream a short response")
  .run { trace in
    trace.chunk(5)
    trace.chunk(7)
    return "Done"
  }
```

## 5) Agent + Tool + Embed + Safety

```swift
import Terra

let plan = try await Terra.agent("planner", id: "agent-42").run {
  let docs = try await Terra.tool("web_search", callID: UUID().uuidString, type: "function").run {
    "search results"
  }

  let embedding = try await Terra.embed("text-embedding-3-small", inputCount: 1).run {
    [[0.11, 0.22, 0.33]]
  }

  let safe = await Terra.safety("toxicity", subject: docs).run { true }
  return "safe=\(safe), vectors=\(embedding.count)"
}

_ = plan
```

## 6) Composable Attr/Capture

```swift
import Terra

let result = try await Terra
  .infer("gpt-4o-mini", prompt: "Hello", provider: "openai", runtime: "http_api")
  .capture(.includeContent)
  .attr(.init("app.request_id"), UUID().uuidString)
  .attr(.init("app.user_tier"), "pro")
  .attr(.init("app.retry"), false)
  .run { trace in
    trace.event("builder.path")
    return "ok"
  }

_ = result
```

## 7) Custom Event and Error Recording

```swift
import Terra

enum APIError: Error { case upstream }

_ = try await Terra.infer("gpt-4o-mini", prompt: "Test").run { trace in
  trace.event("guardrail.decision")
  do {
    throw APIError.upstream
  } catch {
    trace.recordError(error)
  }
  return "ok"
}
```

## 8) `@Traced` Macro

```swift
import TerraTracedMacro

@Traced(model: "gpt-4o-mini", provider: "openai")
func generate(prompt: String) async throws -> String {
  "response: \(prompt)"
}

@Traced(agent: "planner")
func planner() async throws -> String { "done" }
```

## 9) Foundation Models (`TerraFoundationModels`)

```swift
#if canImport(FoundationModels)
import FoundationModels
import TerraFoundationModels

@available(macOS 26.0, iOS 26.0, *)
func runFoundationModels() async throws {
  let session = Terra.TracedSession(model: .default, instructions: "Be concise")
  let text = try await session.respond(to: "Say hello")
  print(text)
}
#endif
```

## 10) MLX (`TerraMLX`)

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
