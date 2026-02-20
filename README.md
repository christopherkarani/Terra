# Terra

[![CI](https://github.com/christopherkarani/Terra/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/christopherkarani/Terra/actions/workflows/ci.yml?query=branch%3Amain)

Terra is observability for on-device GenAI apps in Swift.

It helps you instrument model inference, embeddings, agent steps, tool calls, and safety checks with a focused API, strong privacy defaults, and export/persistence wiring designed for real production environments.

## Why Terra

### For Developers

- Add instrumentation quickly with a small API surface.
- Keep code readable by wrapping only the boundaries you own.
- Use typed helpers for inference, embeddings, agents, tools, and safety checks.
- Extend spans when needed via `Terra.Scope` without dropping to boilerplate everywhere.

### For Enterprise Teams

- Start privacy-safe by default (`contentPolicy: .never`) and enable capture only where explicitly approved.
- Keep telemetry cardinality bounded for predictable backend cost and query performance.
- Route data through OTLP/HTTP into existing observability pipelines.
- Enable on-device persistence for intermittent connectivity and buffered export.
- Standardize GenAI telemetry semantics across apps and model runtimes.

## Quickstart

### 1) Add Terra via SwiftPM

```swift
dependencies: [
  .package(url: "https://github.com/YOUR_ORG/Terra.git", branch: "main"), // replace with your actual repository URL
],
targets: [
  .target(
    name: "YourApp",
    dependencies: [
      .product(name: "Terra", package: "Terra"),
      // Optional:
      // .product(name: "TerraCoreML", package: "Terra"),
      // .product(name: "TerraTraceKit", package: "Terra"),
    ]
  )
]
```

### 2) Install at startup

```swift
import Terra

try Terra.installOpenTelemetry(
  .init(
    enableLogs: false,
    persistence: .init(storageURL: Terra.defaultPersistenceStorageURL())
  )
)

Terra.install(.init(privacy: .default))
```

Notes:
- Call `Terra.installOpenTelemetry(_:)` once per process.
- Reinstalling with a different config throws `Terra.InstallOpenTelemetryError.alreadyInstalled`.
- `Terra.install(_:)` is safe to call again when you want to update privacy/provider overrides in-process.

## Auto-Instrumentation

Terra supports zero-code auto-instrumentation for on-device AI. One line captures everything:

```swift
import Terra

try Terra.start()
```

CoreML note: auto-instrumentation uses a context-based dedup guard to avoid nested spans.
In rare high-concurrency call patterns this may still emit duplicate telemetry.

### Three Tiers of Integration

| Tier | Module | What it does |
|------|--------|-------------|
| Zero-code | `TerraAutoInstrument` | `Terra.start()` — auto-instruments CoreML + HTTP AI APIs |
| One annotation | `TerraTracedMacro` | `@Traced(model:)` — wraps any async function in a span |
| One closure | `TerraMLX` | `TerraMLX.traced(model:) { }` — wraps MLX generation |
| Wrapper | `TerraFoundationModels` | `Terra.TracedSession` — Apple Foundation Models (macOS 26+) |

### Production Usage Notes

- Configure OpenTelemetry before creating spans, ideally at process start.
- Treat persistence as a cache: the default location can be purged by the OS.
- Prefer explicit configuration in production (`Terra.OpenTelemetryConfiguration`) so behavior is deterministic and auditable.

### Customize What Gets Traced

```swift
try Terra.start(.init(
  instrumentations: [.coreML, .httpAIAPIs],
  excludedCoreMLModels: ["background_removal"],
  aiAPIHosts: ["api.openai.com", "api.anthropic.com"]
))
```

High-cost profilers are off by default and must be enabled explicitly:

```swift
try Terra.start(.init(
  profiling: .init(
    enableMemoryProfiler: true,
    enableMetalProfiler: true
  )
))
```

### @Traced Macro

```swift
import TerraTracedMacro

@Traced(model: "llama-3.2-1B")
func summarize(prompt: String, maxTokens: Int = 512) async throws -> String {
  try await container.generate(prompt: prompt, maxTokens: maxTokens)
}
// Auto-detects prompt and maxTokens parameters, wraps body in Terra.withInferenceSpan
```

## Instrumentation API

Use the span helpers around the boundaries you own:

- `Terra.withInferenceSpan(_:_:)`
- `Terra.withEmbeddingSpan(_:_:)`
- `Terra.withAgentInvocationSpan(agent:_:)`
- `Terra.withToolExecutionSpan(tool:call:_:)`
- `Terra.withSafetyCheckSpan(_:_:)`

Each closure gets a `Terra.Scope`:

- `scope.addEvent(_:)`
- `scope.recordError(_:)`
- `scope.setAttributes(_:)`

```swift
import Terra

let agent = Terra.Agent(name: "SupportAgent", id: "agent-123")

try await Terra.withAgentInvocationSpan(agent: agent) { scope in
  scope.addEvent("agent.start")

  try await Terra.withInferenceSpan(.init(model: "local/llama-3.2-1b")) { _ in
    // run model
  }

  try await Terra.withToolExecutionSpan(tool: .init(name: "search"), call: .init(id: "call-1")) { _ in
    // run tool
  }

  scope.addEvent("agent.end")
}
```

## Privacy Defaults

Terra defaults to `Terra.Privacy(contentPolicy: .never)`.

- Raw prompt-like content is not emitted as attributes.
- If capture is enabled, Terra emits bounded metadata (length and optional SHA-256 hash), not raw content.

Opt-in capture pattern:

```swift
Terra.install(.init(privacy: .init(contentPolicy: .optIn, redaction: .hashSHA256)))

let request = Terra.InferenceRequest(
  model: "local/llama-3.2-1b",
  prompt: "Hello",
  promptCapture: .optIn
)

await Terra.withInferenceSpan(request) { _ in }
```

## Metrics and Data Flow

Terra emits lightweight metrics such as:

- `terra.inference.count`
- `terra.inference.duration_ms`

Telemetry destinations:

- Local: signposts for Instruments (when enabled/supported).
- Remote: OTLP/HTTP endpoints for traces/metrics/logs.
- Optional: on-device persistence for offline buffering and later export.

### Persistence Storage (Default Paths)

`Terra.defaultPersistenceStorageURL()` resolves to the platform cache directory and appends `opentelemetry/terra`.

- iOS, tvOS, watchOS, visionOS: `<App Sandbox>/Library/Caches/opentelemetry/terra`
- macOS (sandboxed): `<App Sandbox>/Library/Caches/opentelemetry/terra`
- macOS (non-sandboxed): `~/Library/Caches/opentelemetry/terra`
- If unavailable, Terra falls back to `FileManager.default.temporaryDirectory`.

When persistence is enabled, Terra creates `traces`, `metrics`, and `logs` subdirectories.

### Instrumentation Version

```swift
if let version = Terra.instrumentationVersion {
  print("Terra instrumentation version: \(version)")
}
```

When present, Terra passes it to the tracer provider so spans can be tagged with that version.

## Enterprise Rollout Patterns

- Set privacy globally once at startup, then use per-request opt-in capture only for approved paths.
- Choose `tracerProviderStrategy: .registerNew` for greenfield apps.
- Choose `tracerProviderStrategy: .augmentExisting` when integrating into an app that already configures tracing.
- Keep sessions enabled when you need cross-span session context.
- Keep `Task.detached` out of instrumented paths that require parent/child trace relationships.

## Integrations

- `TerraCoreML`: attach normalized Core ML runtime metadata (`terra.runtime`, `terra.coreml.compute_units`).
- MLX: set low-cardinality runtime attributes (see `Docs/Integrations.md`).
- `TerraTraceKit`: load and model persisted trace files for custom tooling or UIs.

## Trace — macOS Viewer App

Trace is a native macOS app (in `Apps/TraceMacApp/`) for visualizing on-device traces produced by Terra SDK.

**Current capabilities:**
- Load and display traces from a local directory (default: `~/Documents/Terra Traces`).
- Timeline visualization with span hierarchy, lane layout, and duration annotations.
- Dashboard with KPI cards: total traces, spans, error rate, unique agents, p50/p95/p99 latency.
- File system watching for live reload when new traces arrive on disk.
- Diagnostics export (app metadata and file listing for support).
- Configurable trace retention with automatic pruning.

**Not yet implemented (planned):**
- Trace content export (re-emit spans as OTLP JSON for external tools).
- Network-based trace ingestion (OTLP/HTTP receiver for multi-machine workflows).
- Advanced filtering by date range, duration, error status, or span attributes.

> **Note:** The `Enterprise` bullets at the top describe **Terra SDK** library features (OTLP/HTTP export, on-device persistence, privacy controls).
> Trace reads persisted traces from disk; network ingestion is tracked separately.

## Included Products in This Repo

- `Terra`: core instrumentation and runtime install APIs.
- `TerraCoreML`: optional Core ML span attribute helpers.
- `TerraTraceKit`: trace-file discovery, decoding, and view models.
- `TerraSample`: runnable macOS sample app (`swift run TerraSample`).
- `TraceMacApp` / `TraceMacAppUI`: the Trace viewer app and its reusable UI layer.

## Concurrency Behavior

- Structured child tasks inherit active span context.
- `Task.detached` starts without parent span context.

## Requirements

- Swift 6.2 or newer toolchain.
- Platforms: macOS 14+, iOS 13+, tvOS 13+, watchOS 6+, visionOS 1+.
- OTLP-capable backend only if you want remote export.

## Troubleshooting

- `alreadyInstalled`: ensure `Terra.installOpenTelemetry(_:)` is called once, or repeatedly with the exact same configuration.
- Missing remote data: verify endpoint reachability and collector/backend config.
- Missing parent/child spans: replace `Task.detached` with structured concurrency where needed.

## Standards Compatibility

Terra is compatible with OpenTelemetry-based pipelines and semantic conventions, so you can route data to standard collectors/backends without locking into a Terra-specific format.

## CI

This repo runs tests on pull requests using:

- `swift test`
- `swift test --enable-swift-testing`

## License

Apache-2.0. See [LICENSE](https://github.com/christopherkarani/Terra/blob/main/LICENSE).
