# Cookbook

Copy-paste recipes for common Terra instrumentation patterns.

> **Note:** These examples still show `Terra.ModelID` and `Terra.ToolCallID` in a few places for compatibility. New code should prefer raw string model names and `callId:` strings.

## Quickstart

```swift
import Terra

try await Terra.start()
// CoreML and HTTP AI calls are now automatically traced.
```

Other common presets:

```swift
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
        .tool("web-search", callId: "web-search-1")
        .run { "search results" }

    return try await Terra
        .infer(Terra.ModelID("gpt-4o-mini"), prompt: docs)
        .run { "itinerary" }
}
```

## Agentic Workflow Instrumentation

### Multi-Step Agent with Tool Calls

```swift
func runAgent(query: String) async throws -> String {
    let result = try await Terra
        .agent("research-assistant", id: UUID().uuidString)
        .run { trace in
            // Step 1: Web search
            let searchResults = try await Terra
                .tool("web_search", callId: "search-1")
                .run { trace in
                    trace.tag("search.query", query)
                    trace.event("tool.search.start")
                    let results = performWebSearch(query: query)
                    trace.event("tool.search.complete")
                    return results
                }

            // Step 2: Summarize findings
            let summary = try await Terra
                .infer(
                    Terra.ModelID("gpt-4o-mini"),
                    prompt: "Summarize: \(searchResults)"
                )
                .run { trace in
                    trace.tag("step.name", "summarize")
                    trace.tokens(input: 500, output: 100)
                    return try synthesizeResults(searchResults)
                }

            // Step 3: Validate
            let validated = try await Terra
                .tool("validator", callId: "validate-1")
                .run { trace in
                    trace.event("validation.start")
                    return try validateOutput(summary)
                }

            return validated
        }
    return result
}
```

### Sequential Tool Orchestration

```swift
func processWithTools(userRequest: String) async throws -> [String] {
    var results: [String] = []

    // Tool 1: Intent classification
    let intent = try await Terra
        .tool("classify", callId: "classify-1")
        .run { trace in
            trace.tag("user.request", userRequest)
            trace.event("intent.classify")
            return classifyIntent(userRequest)
        }
    results.append(intent)

    // Tool 2: Entity extraction (dependent on intent)
    let entities = try await Terra
        .tool("extract", callId: "extract-1")
        .run { trace in
            trace.tag("intent", intent)
            trace.event("entity.extract")
            return extractEntities(userRequest)
        }
    results.append(contentsOf: entities)

    // Tool 3: Generate response (dependent on both)
    let response = try await Terra
        .infer(Terra.ModelID("gpt-4o-mini"), prompt: "\(intent): \(entities)")
        .run { trace in
            trace.tokens(input: 200, output: 150)
            return generateResponse(intent: intent, entities: entities)
        }
    results.append(response)

    return results
}
```

### Parallel Tool Execution

```swift
func fetchAll(query: String) async throws -> [String] {
    async let web = Terra
        .tool("web_search", callId: "web")
        .run { "web results for \(query)" }

    async let news = Terra
        .tool("news_search", callId: "news")
        .run { "news results for \(query)" }

    async let academic = Terra
        .tool("academic_search", callId: "academic")
        .run { "academic results for \(query)" }

    let (webResults, newsResults, academicResults) = try await (web, news, academic)

    // Synthesize results
    let synthesis = try await Terra
        .infer(Terra.ModelID("gpt-4o-mini"), prompt: "Combine: \(webResults), \(newsResults), \(academicResults)")
        .run { "combined results" }

    return [webResults, newsResults, academicResults, synthesis]
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
    .run { trace in
        trace.tag("app.request_id", UUID().uuidString)
        trace.tag("app.user_tier", "pro")
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

## Error Handling Patterns

### Catch and Record

```swift
try await Terra
    .infer(Terra.ModelID("gpt-4o-mini"), prompt: prompt)
    .run { trace in
        do {
            return try await llm.generate(prompt)
        } catch {
            trace.recordError(error)
            trace.event("inference.fallback")
            throw error
        }
    }
```

### Conditional Error Handling

```swift
let result = try await Terra
    .infer(Terra.ModelID("gpt-4o-mini"), prompt: prompt)
    .run { trace in
        do {
            return try await llm.generate(prompt)
        } catch let error as APIError {
            switch error {
            case .rateLimited:
                trace.tag("error.type", "rate_limit")
                trace.event("retry.scheduled")
            case .timeout:
                trace.tag("error.type", "timeout")
                trace.event("timeout.retry")
            }
            throw error
        }
    }
```

### Error Recovery with Fallback

```swift
func inferWithFallback(prompt: String) async throws -> String {
    do {
        return try await Terra
            .infer(Terra.ModelID("gpt-4o-mini"), prompt: prompt)
            .run { try await primaryModel.generate(prompt) }
    } catch {
        // Fallback to local model
        return try await Terra
            .infer(Terra.ModelID("local-model"), prompt: prompt)
            .run { trace in
                trace.event("inference.fallback")
                return try await localModel.generate(prompt)
            }
    }
}
```

## Custom Configuration

```swift
var config = Terra.Configuration(preset: .production)
config.privacy = .redacted
config.destination = .endpoint(URL(string: "http://127.0.0.1:4318")!)
config.features = [.coreML, .http, .sessions]
config.persistence = .balanced(
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("terra-demo", isDirectory: true)
)
try await Terra.start(config)
```

## Privacy Configuration Recipes

### Maximum Privacy

```swift
var config = Terra.Configuration()
config.privacy = .lengthOnly  // Only record lengths, no hashes
config.features = [.coreML]   // Minimal instrumentation
config.persistence = .off      // No local persistence
try await Terra.start(config)
// Prompts emit: terra.prompt.length = 11
// No content or hashes are recorded
```

### Debug Configuration

```swift
var config = Terra.Configuration()
config.privacy = .capturing  // Capture content with hashing
config.features = [.coreML, .http, .sessions, .signposts, .logs]
config.persistence = .instant(
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TerraDebug")
)
try await Terra.start(config)
// Full telemetry with content for debugging
// Content is HMAC'd for privacy but available for analysis
```

### HIPAA-Compliant Configuration

```swift
var config = Terra.Configuration(preset: .production)
config.privacy = .silent      // Drop all content
config.features = [.coreML]    // Only local inference
config.persistence = .balanced(secureStorageURL)
try await Terra.start(config)
// No PHI leaves the device
```

### Multi-Tenant Privacy

```swift
// Per-request privacy override using capture policy
try await Terra
    .infer(Terra.ModelID("gpt-4o-mini"), prompt: prompt)
    .capture(.includeContent)  // Override default privacy for this call
    .run { trace in
        trace.tag("tenant_id", tenantID)
        trace.tokens(input: 120, output: 60)
        return try await llm.generate(prompt)
    }
```

### Session Privacy Tiers

```swift
enum PrivacyTier {
    case standard   // .redacted
    case debug     // .capturing
    case strict    // .silent

    var config: Terra.Configuration {
        var cfg = Terra.Configuration()
        switch self {
        case .standard:
            cfg.privacy = .redacted
        case .debug:
            cfg.privacy = .capturing
        case .strict:
            cfg.privacy = .silent
        }
        return cfg
    }
}

// Use based on user preference
let userTier: PrivacyTier = .strict
try await Terra.start(userTier.config)
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

## Testing with Telemetry Engine Injection

> **Note:** Telemetry engine injection APIs are `package`-visibility and intended for internal Terra testing. For custom telemetry backends in your own testing, use the `TerraCore` module directly or contact Terra support for testing utilities.

### For Terra SDK Developers

If you're extending TerraCore for custom telemetry engines:

```swift
// Internal testing API (package visibility)
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
```
