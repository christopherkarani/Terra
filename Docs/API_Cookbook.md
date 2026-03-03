# Terra API Cookbook (v3)

Copy-paste recipes for common instrumentation patterns.

## 1) Basic Inference

```swift
import Terra

try Terra.start()

let answer = try await Terra.inference(model: "gpt-4o-mini", prompt: prompt) {
  try await llm.generate(prompt)
}
// Emits one inference span with model/op metadata and duration.
```

## 2) Streaming With TTFT

```swift
import Terra

let output = try await Terra.stream(model: "gpt-4o-mini", prompt: prompt) { trace in
  trace.chunk(tokens: 12)   // first chunk sets TTFT
  trace.chunk(tokens: 18)
  return "final text"
}
// Emits streaming inference metrics (TTFT/TPS) and token counters.
```

## 3) Agent Workflow (Agent + Tool + Inference)

```swift
import Terra

let plan = try await Terra.agent(name: "trip-planner", id: "agent-42") {
  let docs = try await Terra.tool(name: "web-search", callID: UUID().uuidString) { "search results" }
  return try await Terra.inference(model: "gpt-4o-mini", prompt: docs) { "itinerary" }
}
// Emits parent agent span plus child tool and inference spans.
```

## 4) Safety Pipeline

```swift
import Terra

let safe = try await Terra.safetyCheck(name: "input-moderation", subject: userText) { true }
let answer = try await Terra.inference(model: "gpt-4o-mini", prompt: userText) { "response" }
let passed = try await Terra.safetyCheck(name: "output-moderation", subject: answer) { safe }
// Emits safety check spans around inference for policy gates.
```

## 5) Foundation Models Drop-In

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
// Emits traced Foundation Models inference spans with provider/runtime metadata.
```

## 6) Dynamic Metadata With Builder API

```swift
import Terra

let result = try await Terra
  .inference(model: modelName, prompt: prompt)
  .provider(providerName)
  .runtime(runtimeName)
  .attribute(.init("app.experiment"), experimentID)
  .execute { trace in
    trace.tokens(input: 120, output: 60)
    return try await llm.generate(prompt)
  }
// Emits inference span enriched with custom attributes and token usage.
```

## 7) Macro-Based Instrumentation

```swift
import TerraTracedMacro

@Traced(model: "gpt-4o-mini")
func summarize(prompt: String) async throws -> String {
  try await llm.generate(prompt)
}
// Macro expands to Terra.inference(...).execute { ... } with auto-detected params.
```

## 8) Per-Call Privacy Override

```swift
import Terra

var config = Terra.Configuration()
config.privacy = .redacted
try Terra.start(config)

let debug = try await Terra
  .inference(model: "gpt-4o-mini", prompt: prompt)
  .includeContent()
  .execute { try await llm.generate(prompt) }
// Keeps global redaction but allows explicit content capture for this span only.
```
