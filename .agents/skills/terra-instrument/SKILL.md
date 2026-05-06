---
name: terra-instrument
description: Guides a coding agent to scan an iOS/macOS codebase for AI telemetry hotspots (LLM calls, agent loops, tool executions, embeddings, safety checks), wrap them with Terra SDK instrumentation, set up OTLP export, and connect to the TerraViewer dashboard on localhost:4318. Use when a developer wants to add observability to their AI-powered Swift app.
---

# Terra Instrument

## Overview

Terra is an on-device GenAI observability SDK for Swift, built on OpenTelemetry. It instruments model inference, embeddings, agent steps, tool calls, and safety checks across Apple platforms with privacy-first defaults.

This skill walks you through a systematic workflow: scan the codebase for every AI telemetry hotspot, classify each into the right instrumentation tier, apply the correct Terra wrapper, and verify traces flow to the TerraViewer dashboard at `http://localhost:4318`.

The end result: the developer runs their app, opens TerraViewer, and sees every LLM call, agent loop, tool execution, embedding, and safety check as structured OpenTelemetry traces with timing, token counts, and streaming metrics.

---

## Tier Decision Tree

Before instrumenting, classify every hotspot into one of three tiers:

```
Found a hotspot?
├── CoreML MLModel.prediction() calls?
│   └── Tier 1: Zero-code (auto-instrumented by Terra.start())
├── HTTP requests to one of the 8 default AI hosts?
│   └── Tier 1: Zero-code (auto-instrumented by Terra.start())
├── HTTP requests to custom/self-hosted AI endpoints?
│   └── Tier 2: Manual span (withInferenceSpan or add host to aiAPIHosts)
├── Agent orchestration loop?
│   └── Tier 2: Manual span (withAgentInvocationSpan)
├── Tool/function call execution?
│   └── Tier 2: Manual span (withToolExecutionSpan)
├── Embedding generation?
│   └── Tier 2: Manual span (withEmbeddingSpan)
├── Safety/moderation check?
│   └── Tier 2: Manual span (withSafetyCheckSpan)
├── Apple Foundation Models (LanguageModelSession)?
│   └── Tier 3: Framework wrapper (TerraTracedSession)
├── MLX-Swift generation?
│   └── Tier 3: Framework wrapper (TerraMLX.traced)
├── llama.cpp / LlamaSwift?
│   └── Tier 3: Framework wrapper (TerraLlama.traced)
└── Generic async inference function?
    └── Tier 3: @Traced macro
```

**Tier 1** requires only `try Terra.start()` -- zero additional code changes. It auto-instruments CoreML predictions and HTTP requests to these 8 hosts:
- `api.openai.com`
- `api.anthropic.com`
- `generativelanguage.googleapis.com`
- `api.together.xyz`
- `api.mistral.ai`
- `api.groq.com`
- `api.cohere.com`
- `api.fireworks.ai`

**Tier 2** requires wrapping code in `Terra.with*Span()` async closures.

**Tier 3** requires importing a specialized module and using its wrapper type or function.

---

## Codebase Scan Procedure

Follow these steps to find all telemetry hotspots in the user's codebase.

### Step 1: Load search patterns

Load the reference file `references/search_patterns.md` from this skill. It contains all grep and glob patterns organized by category.

### Step 2: Run all patterns

Execute every grep and glob pattern from the reference against the user's Swift source files. Run patterns in parallel where possible. Focus on `**/*.swift` files.

### Step 3: Classify findings

For each match, determine:
1. Which category it belongs to (HTTP AI, CoreML, Foundation Models, MLX, llama.cpp, local servers, agents, tools, embeddings, safety, streaming)
2. Which tier applies (1, 2, or 3)
3. The specific file and function that needs instrumentation

### Step 4: Report summary

Present findings to the user:

```
Scan Results:
- N total hotspots found
  - X auto-instrumented (Tier 1: CoreML + HTTP to default hosts)
  - Y need manual spans (Tier 2: custom APIs, agents, tools, embeddings, safety)
  - Z need framework wrappers (Tier 3: Foundation Models, MLX, llama.cpp)

Tier 1 (zero-code):
  - file.swift:42 — MLModel.prediction (CoreML)
  - NetworkService.swift:108 — api.openai.com (HTTP)

Tier 2 (manual spans):
  - AgentRunner.swift:55 — agent orchestration loop
  - ToolExecutor.swift:23 — tool execution

Tier 3 (framework wrappers):
  - AIService.swift:77 — LanguageModelSession → TerraTracedSession
```

### Step 5: Confirm with user

Ask the user to confirm the plan before proceeding. They may want to skip certain hotspots or add ones that were missed.

---

## Setup Steps

Apply these steps in order. Each step must complete before the next begins.

### Step 1: Add SPM dependency

Add Terra to the project's `Package.swift` or Xcode project:

```swift
// Package.swift
dependencies: [
  .package(url: "https://github.com/christopherkarani/Terra.git", branch: "main"),
]
```

Then add the appropriate products to the target:

```swift
.target(
  name: "YourApp",
  dependencies: [
    // Tier 1: Auto-instrumentation (CoreML + HTTP)
    .product(name: "Terra", package: "Terra"),

    // Tier 3: Only add these if hotspots were found
    .product(name: "TerraFoundationModels", package: "Terra"),  // Apple Foundation Models
    .product(name: "TerraMLX", package: "Terra"),               // MLX-Swift
    .product(name: "TerraLlama", package: "Terra"),             // llama.cpp
    .product(name: "TerraTracedMacro", package: "Terra"),       // @Traced macro
  ]
)
```

**Import rules:**
- `import Terra` — gives you `Terra.start()`, all `with*Span` methods, all request types, privacy types. This is the umbrella module.
- `import TerraCore` — only needed if you are NOT using auto-instrumentation and want manual spans only (rare).
- `import TerraFoundationModels` — only if wrapping `LanguageModelSession`.
- `import TerraMLX` — only if wrapping MLX generation.
- `import TerraLlama` — only if wrapping llama.cpp generation.
- `import TerraTracedMacro` — only if using the `@Traced` macro.

### Step 2: Initialize Terra at app launch

Add `try Terra.start()` as early as possible in the app lifecycle. It **must** execute before any `URLSession` requests or `MLModel.prediction()` calls.

**SwiftUI app:**
```swift
import SwiftUI
import Terra

@main
struct MyApp: App {
  init() {
    do {
      try Terra.start()
    } catch {
      print("Terra init failed: \(error)")
    }
  }

  var body: some Scene {
    WindowGroup { ContentView() }
  }
}
```

**UIKit app:**
```swift
import UIKit
import Terra

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    do {
      try Terra.start()
    } catch {
      print("Terra init failed: \(error)")
    }
    return true
  }
}
```

**Command-line tool / @main struct:**
```swift
import Terra

@main
struct MyCLI {
  static func main() async throws {
    try Terra.start()
    // ... rest of your code
  }
}
```

**Custom configuration (optional):**
```swift
try Terra.start(.init(
  privacy: .init(contentPolicy: .optIn),
  instrumentations: [.coreML, .httpAIAPIs],
  aiAPIHosts: HTTPAIInstrumentation.defaultAIHosts.union([
    "localhost:11434",  // Ollama
    "localhost:1234",   // LM Studio
  ]),
  profiling: .init(
    enableMemoryProfiler: true,
    enableMetalProfiler: true
  )
))
```

At this point, **all Tier 1 hotspots are instrumented**. CoreML predictions and HTTP requests to default AI hosts automatically produce OTel spans.

### Step 3: Instrument Tier 2 hotspots

For each Tier 2 hotspot, wrap the code with the appropriate span method. Load `references/terra_api_reference.md` for exact method signatures.

### Step 4: Instrument Tier 3 hotspots

For each Tier 3 hotspot, replace or wrap with the appropriate framework wrapper.

---

## Instrumentation Recipes

For each hotspot category, here is the before/after transformation. Load `references/terra_api_reference.md` for full type signatures.

### Non-streaming inference

**Before:**
```swift
func askLLM(prompt: String) async throws -> String {
  let response = try await myLLMClient.complete(prompt: prompt, model: "gpt-4")
  return response.text
}
```

**After:**
```swift
func askLLM(prompt: String) async throws -> String {
  try await Terra.withInferenceSpan(.init(model: "gpt-4", prompt: prompt, maxOutputTokens: 1024)) { scope in
    let response = try await myLLMClient.complete(prompt: prompt, model: "gpt-4")
    scope.setAttributes([
      "gen_ai.usage.input_tokens": .int(response.inputTokens),
      "gen_ai.usage.output_tokens": .int(response.outputTokens),
    ])
    return response.text
  }
}
```

### Streaming inference

**Before:**
```swift
func streamLLM(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
  return myLLMClient.stream(prompt: prompt, model: "gpt-4")
}
```

**After:**
```swift
func streamLLM(prompt: String) async throws {
  try await Terra.withStreamingInferenceSpan(.init(model: "gpt-4", prompt: prompt)) { streamScope in
    for try await chunk in myLLMClient.stream(prompt: prompt, model: "gpt-4") {
      streamScope.recordChunk()
      streamScope.recordToken()
      // process chunk...
    }
  }
}
```

Key `StreamingInferenceScope` methods:
- `recordToken(_ count: Int = 1)` — incremental token count; first call sets TTFT
- `recordOutputTokenCount(_ totalCount: Int)` — absolute token count; first call sets TTFT
- `recordChunk()` — chunk arrival; first call sets TTFT

On span finish, these derived attributes are computed automatically:
- `terra.stream.time_to_first_token_ms`
- `terra.stream.tokens_per_second`
- `terra.stream.output_tokens`
- `terra.stream.chunk_count`

### Agent orchestration loop

**Before:**
```swift
func runAgent(task: String) async throws -> String {
  var result = ""
  for step in 0..<maxSteps {
    let thought = try await thinkStep(task: task, history: result)
    let action = try await decideAction(thought: thought)
    let observation = try await executeAction(action)
    result += observation
    if isDone(observation) { break }
  }
  return result
}
```

**After:**
```swift
func runAgent(task: String) async throws -> String {
  try await Terra.withAgentInvocationSpan(agent: .init(name: "ReActAgent", id: "agent-1")) { agentScope in
    var result = ""
    for step in 0..<maxSteps {
      agentScope.addEvent("agent.step", attributes: ["step": .int(step)])

      let thought = try await Terra.withInferenceSpan(.init(model: "gpt-4", prompt: task)) { _ in
        try await thinkStep(task: task, history: result)
      }

      let action = try await decideAction(thought: thought)

      let observation = try await Terra.withToolExecutionSpan(
        tool: .init(name: action.toolName),
        call: .init(id: "call-\(step)")
      ) { _ in
        try await executeAction(action)
      }

      result += observation
      if isDone(observation) { break }
    }
    return result
  }
}
```

### Tool execution

**Before:**
```swift
func executeSearch(query: String) async throws -> [Result] {
  return try await searchAPI.search(query)
}
```

**After:**
```swift
func executeSearch(query: String, callID: String) async throws -> [Result] {
  try await Terra.withToolExecutionSpan(
    tool: .init(name: "web_search", type: "function"),
    call: .init(id: callID)
  ) { scope in
    let results = try await searchAPI.search(query)
    scope.addEvent("tool.results", attributes: ["result_count": .int(results.count)])
    return results
  }
}
```

### Embeddings

**Before:**
```swift
func embed(texts: [String]) async throws -> [[Float]] {
  return try await embeddingClient.embed(texts, model: "text-embedding-3-small")
}
```

**After:**
```swift
func embed(texts: [String]) async throws -> [[Float]] {
  try await Terra.withEmbeddingSpan(.init(model: "text-embedding-3-small", inputCount: texts.count)) { scope in
    let vectors = try await embeddingClient.embed(texts, model: "text-embedding-3-small")
    return vectors
  }
}
```

### Safety checks

**Before:**
```swift
func moderateContent(_ text: String) async throws -> Bool {
  let result = try await moderationAPI.check(text)
  return result.isSafe
}
```

**After:**
```swift
func moderateContent(_ text: String) async throws -> Bool {
  try await Terra.withSafetyCheckSpan(.init(name: "content_moderation", subject: text)) { scope in
    let result = try await moderationAPI.check(text)
    scope.addEvent(result.isSafe ? "safety.passed" : "safety.flagged")
    return result.isSafe
  }
}
```

### Apple Foundation Models (Tier 3)

**Before:**
```swift
import FoundationModels

let session = LanguageModelSession()
let response = try await session.respond(to: "Summarize this article")
print(response.content)
```

**After:**
```swift
import Terra
import TerraFoundationModels

let session = TerraTracedSession()  // also aliased as Terra.TracedSession
let response = try await session.respond(to: "Summarize this article")
print(response)
```

For structured output with `@Generable`:
```swift
let result = try await session.respond(to: "Extract entities", generating: MyStruct.self)
```

For streaming:
```swift
for try await chunk in session.streamResponse(to: "Tell me a story") {
  print(chunk, terminator: "")
}
```

### MLX-Swift (Tier 3)

**Before:**
```swift
import MLX
let result = try await container.generate(prompt: prompt, maxTokens: 256)
```

**After:**
```swift
import Terra
import TerraMLX

let result = try await TerraMLX.traced(model: "mlx-community/Llama-3.2-1B", maxTokens: 256) {
  try await container.generate(prompt: prompt, maxTokens: 256)
}
```

For token-by-token tracking inside the closure, use the active span helpers:
```swift
// In your didGenerate callback:
if tokenCount == 1 { TerraMLX.recordFirstToken() }
TerraMLX.recordTokenCount(tokenCount)
```

### llama.cpp (Tier 3)

**Before:**
```swift
let output = try await llamaModel.generate(prompt: "Hello", maxTokens: 128)
```

**After:**
```swift
import Terra
import TerraLlama

let output = try await TerraLlama.traced(model: "llama-3.2-1B-Q4", prompt: "Hello") { streamScope in
  var tokens = ""
  for try await token in llamaModel.generate(prompt: "Hello", maxTokens: 128) {
    streamScope.recordToken()
    tokens += token
  }
  return tokens
}
```

### @Traced macro (Tier 3)

For any async function that does inference, the `@Traced` macro auto-wraps the body:

**Before:**
```swift
func generate(prompt: String, maxTokens: Int = 512) async throws -> String {
  try await container.generate(prompt: prompt, maxTokens: maxTokens)
}
```

**After:**
```swift
import TerraTracedMacro

@Traced(model: "llama-3.2-1B")
func generate(prompt: String, maxTokens: Int = 512) async throws -> String {
  try await container.generate(prompt: prompt, maxTokens: maxTokens)
}
```

The macro auto-detects parameters named `prompt`/`input`/`query`/`text` and `maxTokens`/`maxOutputTokens`/`max_tokens`. **Async functions only.**

---

## Span Hierarchy Best Practices

Terra uses OpenTelemetry context propagation. Child spans automatically link to their parent within the same async context.

### Context propagation rules

- `async let` preserves parent-child: child span gets the parent's traceID.
- `Task { }` preserves parent-child: inherits the structured concurrency context.
- `Task.detached { }` **breaks context**: creates a new trace. **Avoid using `Task.detached` inside instrumented code.**
- `TaskGroup` / `withTaskGroup` preserves parent-child for each child task.

### Common span hierarchies

**RAG pipeline:**
```
gen_ai.agent (RAG Pipeline)
├── gen_ai.embeddings (query embedding)
├── gen_ai.tool (vector search)
├── gen_ai.inference (LLM with retrieved context)
└── terra.safety_check (output moderation)
```

**Multi-agent system:**
```
gen_ai.agent (Orchestrator)
├── gen_ai.agent (Research Agent)
│   ├── gen_ai.inference (think)
│   └── gen_ai.tool (web search)
├── gen_ai.agent (Writing Agent)
│   ├── gen_ai.inference (draft)
│   └── gen_ai.inference (revise)
└── terra.safety_check (final check)
```

**Conversational bot:**
```
gen_ai.agent (Conversation Turn)
├── terra.safety_check (input moderation)
├── gen_ai.inference (streaming response)
└── terra.safety_check (output moderation)
```

---

## Dashboard Connection

### Step 1: Get TerraViewer

Download and run TerraViewer from: `https://github.com/christopherkarani/TerraViewer`

TerraViewer is a standalone macOS app that receives OTLP traces over HTTP.

### Step 2: Verify endpoint

TerraViewer listens on `http://localhost:4318`. Terra's default OTLP traces endpoint is `http://localhost:4318/v1/traces` -- this is auto-configured by `Terra.start()`, so no manual endpoint configuration is needed.

### Step 3: Run and observe

1. Launch TerraViewer
2. Run the instrumented app
3. Traces appear in real-time in TerraViewer's timeline

Each span shows:
- Operation name and duration
- Model name, token counts, temperature
- Streaming metrics (TTFT, tokens/sec, chunk count)
- Memory delta and thermal state (if profiling enabled)
- Error details (if the span recorded an error)
- Parent-child hierarchy (nested spans)

---

## Verification

After instrumentation, verify everything works:

### Build check

```bash
swift build
```
The project must compile without errors. Common issues:
- Missing `import Terra` or framework-specific import
- Wrong product name in `Package.swift` dependencies
- Using `@Traced` on a non-async function

### Runtime check

1. Launch TerraViewer
2. Run the app and trigger at least one AI operation
3. Confirm at least one trace appears in TerraViewer within 5 seconds

### Signpost check (optional)

Open Console.app, filter by `io.opentelemetry.terra`. Terra spans emit signposts visible in Instruments and Console.app when `enableSignposts` is true (default).

---

## Troubleshooting

### No traces appearing in TerraViewer

1. **Late initialization:** `Terra.start()` was called AFTER the first `URLSession` or `MLModel` call. Move it to app launch.
2. **TerraViewer not running:** Ensure TerraViewer is open and listening on port 4318 before the app sends traces.
3. **Wrong endpoint:** If using a custom `OpenTelemetryConfiguration`, verify `otlpTracesEndpoint` is `http://localhost:4318/v1/traces`.
4. **App Transport Security:** For non-localhost endpoints, ensure ATS allows the connection. Localhost is exempt from ATS.

### Double-counted spans

**Double initialization:** `Terra.start()` called more than once. It is idempotent with the same config, but throws `InstallOpenTelemetryError.alreadyInstalled` if called with different configs. Guard with a once flag or `DispatchQueue.once`.

### Detached tasks break trace hierarchy

`Task.detached { }` creates a new trace context. Spans inside detached tasks will not appear as children of the outer span. Replace with `Task { }` to preserve context propagation.

### Ollama / LM Studio not auto-instrumented

`localhost:11434` (Ollama) and `localhost:1234` (LM Studio) are NOT in the default 8 AI hosts. Add them explicitly:

```swift
try Terra.start(.init(
  aiAPIHosts: HTTPAIInstrumentation.defaultAIHosts.union([
    "localhost:11434",
    "localhost:1234",
  ])
))
```

### Wrong import for Tier 2 only

If you only need manual spans (no auto-instrumentation), use `import TerraCore` instead of `import Terra`. But in most cases, just use `import Terra` which re-exports `TerraCore`.

### @Traced macro on non-async function

The `@Traced` macro only works on `async` functions. It will produce a compile error on synchronous functions. Wrap synchronous code in an async context or use `withInferenceSpan` directly.

---

## Resources

### references/

- `terra_api_reference.md` — Complete API reference with all method signatures, types, attribute keys, and framework wrappers. Load when you need exact type information.
- `search_patterns.md` — All grep/glob patterns for codebase scanning. Load at the start of the scan procedure.
