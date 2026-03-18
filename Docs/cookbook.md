# Cookbook

Copy-paste recipes for common Terra instrumentation patterns.

## Quickstart

```swift
import Terra

try await Terra.start()
// CoreML and HTTP AI calls are now automatically traced.
// Use presets for different environments:
try await Terra.start(.init(preset: .production))
try await Terra.start(.init(preset: .diagnostics))
```

## Inference

```swift
let answer = try await Terra
    .infer(Terra.ModelID("gpt-4o-mini"), prompt: prompt)
    .run { try await llm.generate(prompt) }
```

With metadata:

```swift
let answer = try await Terra
    .infer(
        Terra.ModelID("gpt-4o-mini"),
        prompt: prompt,
        provider: Terra.ProviderID("openai"),
        runtime: Terra.RuntimeID("http_api"),
        temperature: 0.2,
        maxTokens: 300
    )
    .run { trace in
        trace.tokens(input: 120, output: 70)
        trace.responseModel(Terra.ModelID("gpt-4o-mini"))
        return try await llm.generate(prompt)
    }
```

## Streaming

```swift
let output = try await Terra
    .stream(Terra.ModelID("gpt-4o-mini"), prompt: prompt)
    .run { trace in
        trace.chunk(12)
        trace.chunk(18)
        return "final text"
    }
```

## Agent Workflow

Nest agents, tools, and inference naturally:

```swift
let plan = try await Terra.agent("trip-planner", id: "agent-42").run {
    let docs = try await Terra
        .tool("web-search", callID: Terra.ToolCallID())
        .run { "search results" }

    return try await Terra
        .infer(Terra.ModelID("gpt-4o-mini"), prompt: docs)
        .run { "itinerary" }
}
```

## Embeddings

```swift
let vectors = try await Terra
    .embed(Terra.ModelID("text-embedding-3-small"), inputCount: 1)
    .run { [[0.11, 0.22, 0.33]] }
```

## Safety Pipeline

```swift
let safe = try await Terra
    .safety("input-moderation", subject: userText)
    .run { true }

let answer = try await Terra
    .infer(Terra.ModelID("gpt-4o-mini"), prompt: userText)
    .run { "response" }

let passed = try await Terra
    .safety("output-moderation", subject: answer)
    .run { safe }
```

## Custom Attributes and Capture

```swift
let result = try await Terra
    .infer(
        Terra.ModelID("gpt-4o-mini"),
        prompt: prompt,
        provider: Terra.ProviderID("openai"),
        runtime: Terra.RuntimeID("http_api")
    )
    .capture(.includeContent)
    .attr(.init("app.request_id"), UUID().uuidString)
    .attr(.init("app.user_tier"), "pro")
    .run { trace in
        trace.tokens(input: 120, output: 60)
        return try await llm.generate(prompt)
    }
```

## Error Recording

```swift
_ = try await Terra
    .infer(Terra.ModelID("gpt-4o-mini"), prompt: "Test")
    .run { trace in
        trace.event("guardrail.decision")
        do {
            throw APIError.upstream
        } catch {
            trace.recordError(error)
        }
        return "ok"
    }
```

## Custom Configuration

```swift
var config = Terra.Configuration()
config.privacy = .redacted
config.endpoint = URL(string: "http://127.0.0.1:4318")!
config.serviceName = "com.example.app"
config.serviceVersion = "3.0.0"
config.persistence = .defaults()
try await Terra.start(config)
```

## `@Traced` Macro

```swift
import TerraTracedMacro

@Traced(model: Terra.ModelID("gpt-4o-mini"))
func summarize(prompt: String) async throws -> String {
    try await llm.generate(prompt)
}

@Traced(agent: "planner")
func planner() async throws -> String { "done" }
```

## Foundation Models

```swift
#if canImport(FoundationModels)
import FoundationModels
import TerraFoundationModels

@available(macOS 26.0, iOS 26.0, *)
func ask(_ prompt: String) async throws -> String {
    let session = Terra.TracedSession(model: .default)
    return try await session.respond(to: prompt)
}
#endif
```

## MLX

```swift
import TerraMLX

let text = try await TerraMLX.traced(
    model: Terra.ModelID("mlx-community/Llama-3.2-1B"),
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
```

## Engine Injection (Testing)

Replace the telemetry backend for deterministic tests:

```swift
struct TestEngine: Terra.TelemetryEngine {
    func run<R: Sendable>(
        context: Terra.TelemetryContext,
        attributes: [Terra.TraceAttribute],
        _ body: @escaping @Sendable (Terra.TraceHandle) async throws -> R
    ) async throws -> R {
        let trace = Terra.TraceHandle(
            onEvent: { _ in },
            onAttribute: { _, _ in },
            onError: { _ in }
        )
        return try await body(trace)
    }
}

let result = try await Terra
    .tool("search", callID: Terra.ToolCallID("call-1"))
    .run(using: TestEngine()) { trace in
        trace.event("tool.mocked")
        return "stubbed"
    }
```
