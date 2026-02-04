# Terra

Terra is an **on-device GenAI observability façade** for Swift 6.2 model runtimes and agents, built on **OpenTelemetry Swift**.

It gives you a small, misuse-resistant API to instrument inference/agent boundaries, while keeping export/wiring and backend-specific enrichment (Core ML, MLX, etc.) optional.

## Requirements

- Swift 6.2 (or newer toolchain)
- Platforms: macOS 12+, iOS 13+, tvOS 13+, watchOS 6+, visionOS 1+
- An OTLP-capable backend (for remote export), usually via an OpenTelemetry Collector

## Add Terra to Your Project (SwiftPM)

In your app/package `Package.swift`:

```swift
dependencies: [
  // Pin to a tag/branch/commit in your own integration.
  .package(url: "https://github.com/your-org/Terra.git", branch: "main"),
],
targets: [
  .target(
    name: "YourApp",
    dependencies: [
      .product(name: "Terra", package: "Terra"),
      // Optional Core ML helpers:
      // .product(name: "TerraCoreML", package: "Terra"),
    ]
  )
]
```

## Quickstart (2 Calls at App Startup)

```swift
import Terra

// 1) One-call OpenTelemetry wiring (OTLP/HTTP + optional on-device persistence + Signposts + Sessions).
try Terra.installOpenTelemetry(
  .init(
    enableLogs: false,
    persistence: .init(storageURL: Terra.defaultPersistenceStorageURL())
  )
)

// 2) Terra privacy defaults (recommended).
Terra.install(.init(privacy: .default))
```

Notes:
- Call `Terra.installOpenTelemetry(_:)` **once** per process; calling it again with a different configuration throws `Terra.InstallOpenTelemetryError.alreadyInstalled`.
- `Terra.install(_:)` is safe to call to update Terra’s in-process configuration (privacy/provider overrides).

## Instrument the Boundaries You Own

Terra’s public API is a small set of span helpers:

- `Terra.withInferenceSpan(_:_:)`
- `Terra.withEmbeddingSpan(_:_:)`
- `Terra.withAgentInvocationSpan(agent:_:)`
- `Terra.withToolExecutionSpan(tool:call:_:)`
- `Terra.withSafetyCheckSpan(_:_:)`

Each closure receives a `Terra.Scope` with:
- `scope.addEvent(_:)`
- `scope.recordError(_:)`
- `scope.setAttributes(_:)`

Example:

```swift
import Terra

let agent = Terra.Agent(name: "SupportAgent", id: "agent-123")

try await Terra.withAgentInvocationSpan(agent: agent) { scope in
  scope.addEvent("agent.start")

  try await Terra.withInferenceSpan(.init(model: "local/llama-3.2-1b")) { _ in
    // ... run your model/runtime
  }

  try await Terra.withToolExecutionSpan(tool: .init(name: "search"), call: .init(id: "call-1")) { _ in
    // ... run your tool
  }

  scope.addEvent("agent.end")
}
```

## Privacy (Default Safe)

By default, prompt-like fields are **not captured** (`Terra.Privacy(contentPolicy: .never)`).

To enable *opt-in* capture (recommended), configure Terra once and then opt in per request:

```swift
Terra.install(.init(privacy: .init(contentPolicy: .optIn, redaction: .hashSHA256)))

let request = Terra.InferenceRequest(
  model: "local/llama-3.2-1b",
  prompt: "Hello",
  promptCapture: .optIn
)
await Terra.withInferenceSpan(request) { _ in }
```

Terra never emits raw prompt content as attributes; it emits bounded metadata like length and (when available) SHA-256.

## Where Data Goes

- **Local dev:** when `enableSignposts` is on (default), Terra installs Signpost processors so spans are visible in Instruments (where supported by OS version).
- **Remote export:** traces/metrics/logs (optional) are exported via **OTLP/HTTP** to the configured endpoints; on-device persistence can buffer data across restarts/offline periods.

## Metrics

Terra records lightweight, low-cardinality metrics (when OpenTelemetry metrics are enabled), including:

- `terra.inference.count`
- `terra.inference.duration_ms`

## Sample App

Run the included sample (macOS only):

```bash
swift run TerraSample
```

The sample lives at `Examples/Terra Sample/main.swift` and demonstrates agent + inference + tool spans.

## Integrations

- Core ML helpers: `TerraCoreML` (see `Sources/TerraCoreML/TerraCoreML.swift`)
- Recommended attribute patterns for Core ML + MLX: `Docs/Integrations.md`

## Concurrency Expectations

Terra relies on OpenTelemetry Swift context propagation:

- Structured child tasks (e.g. `async let`, `Task {}`) inherit the active span context.
- `Task.detached` does **not** inherit span context (it starts a new trace root).

## Semantic Conventions (Span Names + Keys)

Span names:
- `gen_ai.inference`, `gen_ai.embeddings`, `gen_ai.agent`, `gen_ai.tool`, `terra.safety_check`

Key prefixes:
- Prefer `gen_ai.*` when applicable (model, operation, agent/tool identity).
- Use `terra.*` for device/runtime/privacy extensions.

## Troubleshooting

- `alreadyInstalled`: ensure `Terra.installOpenTelemetry(_:)` is only called once per process (or called repeatedly with the exact same configuration).
- No remote data: confirm your OTLP/HTTP endpoints are reachable from the device/simulator and match your collector/backend configuration.
- Missing parent/child relationships: avoid `Task.detached` when you want spans to share context; prefer structured concurrency.

---

- Provides a small Swift 6.2 API for on-device GenAI observability on OpenTelemetry Swift.
- Supports turnkey OTLP/HTTP export with optional persistence, signposts, and sessions via `Terra.installOpenTelemetry(_:)`.
- Defaults to privacy-safe behavior; prompt-like capture is explicit opt-in with redaction.
- Includes a macOS sample and integration guidance for Core ML and MLX.
