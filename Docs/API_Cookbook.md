# Terra API Cookbook (Current)

Copy-paste recipes for common instrumentation patterns.

## 1) Basic Inference

```swift
import Terra

try Terra.start()

let answer = try await Terra.infer("gpt-4o-mini", prompt: prompt).run {
  try await llm.generate(prompt)
}
```

## 2) Streaming With Token Progress

```swift
import Terra

let output = try await Terra.stream("gpt-4o-mini", prompt: prompt).run { trace in
  trace.chunk(12)
  trace.chunk(18)
  return "final text"
}
```

## 3) Agent Workflow (Agent + Tool + Inference)

```swift
import Terra

let plan = try await Terra.agent("trip-planner", id: "agent-42").run {
  let docs = try await Terra.tool("web-search", callID: UUID().uuidString).run { "search results" }
  return try await Terra.infer("gpt-4o-mini", prompt: docs).run { "itinerary" }
}
```

## 4) Safety Pipeline

```swift
import Terra

let safe = try await Terra.safety("input-moderation", subject: userText).run { true }
let answer = try await Terra.infer("gpt-4o-mini", prompt: userText).run { "response" }
let passed = try await Terra.safety("output-moderation", subject: answer).run { safe }
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
```

## 6) Dynamic Metadata With Composable Calls

```swift
import Terra

let result = try await Terra
  .infer(modelName, prompt: prompt, provider: providerName, runtime: runtimeName)
  .attr(.init("app.experiment"), experimentID)
  .attr(.init("app.retry"), false)
  .run { trace in
    trace.tokens(input: 120, output: 60)
    return try await llm.generate(prompt)
  }
```

## 7) Per-Call Capture Override

```swift
import Terra

var config = Terra.Configuration()
config.privacy = .redacted
try Terra.start(config)

let debug = try await Terra
  .infer("gpt-4o-mini", prompt: prompt)
  .capture(.includeContent)
  .run { try await llm.generate(prompt) }
```

## 8) Macro-Based Instrumentation

```swift
import TerraTracedMacro

@Traced(model: "gpt-4o-mini")
func summarize(prompt: String) async throws -> String {
  try await llm.generate(prompt)
}
```
