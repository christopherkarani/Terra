# Terra

**Observe your AI app. One line of Swift.**

Terra is a Swift-native telemetry SDK that traces AI workflows — inference calls, tool executions, streaming generations, embeddings, and safety checks — and sends them to OpenTelemetry. It includes a built-in local trace viewer, system profilers, and one-line auto-instrumentation for CoreML, MLX, and Foundation Models.

```swift
import Terra

try await Terra.start()

try await Terra.workflow(name: "chat.request") { workflow in
  try await workflow.infer("gpt-4o-mini", prompt: "Hello") { span in
    span.tokens(input: 4, output: 12)
    return "Hello! How can I help you?"
  }
}
```

**What you get:** OpenTelemetry spans exported to any collector, a local trace server you can browse, and zero-code auto-instrumentation for Apple's AI stack.

---

## What Terra Does

AI apps are black boxes. You fire off a prompt, a tool runs, a stream chunks back — but you can't see the latency, token counts, tool call sequences, or failures without sprinkling print statements everywhere.

Terra turns that into structured telemetry:

```
┌─ Workflow: chat.request ──────────────────────────────┐
│  ├─ Inference: gpt-4o-mini ............ 145 ms       │
│  │   input_tokens: 24  output_tokens: 14              │
│  ├─ Tool: search ......................  32 ms       │
│  │   result: "docs"                                   │
│  └─ Stream: gpt-4o-mini ..............  89 ms       │
│      first_token_latency: 120 ms                      │
└───────────────────────────────────────────────────────┘
```

Every workflow produces an OpenTelemetry trace. View traces locally with `TerraTraceKit`, export them to Jaeger/Grafana/Honeycomb, or inspect them in the Xcode console.

---

## Installation

### Swift Package Manager

Add Terra to your `Package.swift`:

```swift
dependencies: [
  .package(url: "https://github.com/earendil-works/terra.git", from: "1.0.0")
]
```

Or in Xcode: **File → Add Package Dependencies →** `https://github.com/earendil-works/terra.git`

### Products

| Product | What to import | Purpose |
|---------|---------------|---------|
| `Terra` | `import Terra` | Auto-instrumentation umbrella. Start here. |
| `TerraCore` | `import TerraCore` | Manual tracing, workflows, spans, privacy controls. |
| `TerraTraceKit` | `import TerraTraceKit` | Local OTLP server, trace storage, timeline rendering. |
| `TerraMLX` | `import TerraMLX` | One-line tracing for MLX Swift generation. |
| `TerraFoundationModels` | `import TerraFoundationModels` | Traced wrapper for Apple Foundation Models. |
| `TerraCoreML` | `import TerraCoreML` | CoreML prediction telemetry. |
| `TerraTracedMacro` | `import TerraTracedMacro` | `@Traced` macro for zero-boilerplate span creation. |

---

## 30-Second Quickstart

```swift
import Terra

// 1. Start telemetry (exports to OTLP localhost:4318 by default)
try await Terra.start()

// 2. Wrap one request in a workflow
try await Terra.workflow(name: "ask") { workflow in
  let answer = try await workflow.infer("gpt-4o-mini", prompt: "What is Swift?") { span in
    span.tokens(input: 4, output: 24)
    return "Swift is a fast, safe programming language."
  }
  print(answer)
}

// 3. (Optional) view traces locally, export to your collector,
//    or run Terra.diagnose() to verify your setup.
```

> **New to tracing?** Run `print(Terra.help())` and `let report = Terra.diagnose()` after starting Terra to see runtime guidance and a health check.

---

## Real Integration: OpenAI + Terra

Terra does not replace your AI client — it wraps it. Here is a real pattern using `URLSession`:

```swift
import Terra

let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]!

try await Terra.workflow(name: "support.agent", id: "req-42") { workflow in
  let prompt = "Summarize the latest crash report."

  let summary = try await workflow.infer("gpt-4o-mini", prompt: prompt) { span in
    // Make your actual HTTP request inside the span
    var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
    request.httpMethod = "POST"
    request.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode([
      "model": "gpt-4o-mini",
      "messages": [["role": "user", "content": prompt]]
    ])

    let (data, response) = try await URLSession.shared.data(for: request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let content = ((json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String

    // Record telemetry
    span.tokens(input: prompt.count / 4, output: content?.count ?? 0)
    return content ?? ""
  }

  print(summary)
}
```

For **zero-code** HTTP AI API tracing, add `TerraHTTPInstrument` and call `HTTPAIInstrumentation.install()`.

---

## Architecture

Terra traces follow a simple hierarchy:

```
Workflow (root span)
  ├─ Inference span   – LLM call with token counts, model name, latency
  ├─ Stream span      – Streaming generation with first-token and chunk metrics
  ├─ Tool span        – Tool/function execution with call ID and result
  ├─ Embed span       – Embedding request
  ├─ Safety span      – Safety/guardrail check
  └─ Agent span       – Multi-step agent loop
```

Use **one workflow per user request or agent turn**. All child spans attach automatically. If a tool call is discovered inside a stream but executed later, capture `span.handoff()` before the child closes.

---

## Viewing Traces

### Local OTLP Server (TerraTraceKit)

`TerraTraceKit` includes an embedded OTLP HTTP server and trace store. Use it to build a local trace viewer or ingest from other OpenTelemetry sources:

```swift
import TerraTraceKit

let store = TraceStore(maxSpans: 10_000)
let server = OTLPHTTPServer(traceStore: store)
try server.start()
print("Trace server running on http://localhost:\(server.port)")
```

### Export to Any Collector

Configure Terra to export traces to Jaeger, Grafana Tempo, Honeycomb, or any OTLP-compatible backend:

```swift
var config = Terra.Configuration(preset: .production)
config.destination = .endpoint(URL(string: "https://your-collector.example.com")!)
try await Terra.start(config)
```

### File-Based Traces

Terra can persist traces to local files for offline debugging:

```swift
var config = Terra.Configuration()
config.persistence = .file(directory: URL(fileURLWithPath: "/tmp/terra-traces"))
try await Terra.start(config)
```

---

## Auto-Instrumentation Tiers

| Tier | Code | What it traces |
|------|------|---------------|
| **1. Zero-code** | `try await Terra.start()` | CoreML predictions, HTTP AI API calls |
| **2. One annotation** | `@Traced(model: "llama-3.2")` | Any `async` function with auto parameter capture |
| **3. One closure** | `TerraMLX.traced(model:) { ... }` | MLX Swift generation with streaming metrics |
| **4. One session** | `Terra.TracedSession(...)` | Apple Foundation Models (macOS 26+/iOS 26+) |

---

## Platforms

Terra supports **macOS 14+**, **iOS 13+**, **tvOS 13+**, **watchOS 6+**, and **visionOS 1+**.

The Swift-native APIs run on every platform. The optional Zig-backed C ABI core (`TERRA_USE_ZIG_CORE`) is packaged for macOS via `Vendor/libtera.xcframework`.

See [Docs/PLATFORM-COMPATIBILITY.md](Docs/PLATFORM-COMPATIBILITY.md) for the full matrix.

---

## Cookbook

### Streaming

```swift
let streamed = try await Terra.workflow(name: "stream.request") { workflow in
  try await workflow.stream("gpt-4o-mini", prompt: "Explain") { span in
    span.firstToken()
    span.chunk(4)
    span.outputTokens(12)
    return "done"
  }
}
```

### Mutable Transcript

```swift
var messages = [Terra.ChatMessage(role: "user", content: "Plan the fix.")]

let result = try await Terra.workflow(name: "planner", messages: &messages) { workflow, transcript in
  workflow.checkpoint("planning")
  await transcript.append(.init(role: "assistant", content: "Draft plan"))
  return "ok"
}
```

### Deferred Tool Handoff

```swift
let result = try await Terra.workflow(name: "tool.after.stream") { workflow in
  let deferred = try await workflow.stream("gpt-4o-mini", prompt: "Explain") { span in
    span.firstToken()
    return try span.handoff().tool("search", callId: "search-1", type: "web_search")
  }
  return try await deferred.run { "docs" }
}
```

### Manual Parent Span

```swift
let parent = Terra.startSpan(name: "manual.request")
defer { parent.end() }

_ = try await Terra.tool("search", callId: "manual-1").under(parent).run { "ok" }
```

More recipes: [Docs/cookbook.md](Docs/cookbook.md)

---

## Profilers

Terra includes opt-in profilers for on-device AI performance analysis:

- **TerraMetalProfiler** — GPU/Metal compute attribution
- **TerraSystemProfiler** — Memory snapshots, thermal monitoring, thread timing
- **TerraCoreML** — Espresso log capture, model size detection, compute-plan metrics
- **TerraPowerProfiler** — Power domain sampling (macOS)
- **TerraANEProfiler** — Apple Neural Engine hardware metrics (opt-in, Developer ID only)

See [Docs/Profiler-Integration.md](Docs/Profiler-Integration.md).

---

## Discovery & Diagnostics

Run these anytime after starting Terra:

```swift
Terra.help()           // Print usage hints
Terra.diagnose()       // Health check and configuration report
Terra.ask("workflow with tools")  // Query-style API guidance
Terra.examples()       // List canonical code snippets
Terra.guides()         // List available documentation
Terra.playground()     // Interactive exploration hints
```

---

## Bindings & Robotics

Terra exposes a stable C ABI and bindings for Rust, Python, Kotlin/Android, and C++. Drone and robotics teams can use the ROS 2 bridge and callback-backed UART/MQTT/CoAP transports.

- [Docs/BINDING_CONFORMANCE.md](Docs/BINDING_CONFORMANCE.md)
- [Docs/ROBOTICS-PILOT.md](Docs/ROBOTICS-PILOT.md)
- [terra-ros2/README.md](terra-ros2/README.md)

---

## Documentation

- [Docs/PUBLIC-API-COVERAGE.md](Docs/PUBLIC-API-COVERAGE.md) — Source-backed API matrix
- [Docs/integrations.md](Docs/integrations.md) — Foundation Models, MLX, CoreML
- [Docs/migration.md](Docs/migration.md) — Migrating from legacy APIs
- [Docs/cookbook.md](Docs/cookbook.md) — Full recipe collection
- [CHANGELOG.md](CHANGELOG.md)

---

## License

Apache 2.0
