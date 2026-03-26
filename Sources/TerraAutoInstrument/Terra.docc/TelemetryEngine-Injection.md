# Protocol Seams

> **Note:** These APIs are `package` scoped — intended for internal use within the Terra package or by companion packages, not for public SDK consumption.

Use ``Terra/TelemetryEngine`` to inject deterministic execution for tests or custom runtimes inside the Terra package or companion packages that share package access.

## Core Seam Types

- ``Terra/TelemetryEngine`` (`package`)
- ``Terra/TelemetryContext`` (`package`)
- ``Terra/TraceHandle`` (`public`)

The seam entry point is ``Terra/Operation/run(using:_:)`` (`package`).
Engine implementers handle ``Terra/TelemetryEngine/run(context:attributes:_:)``.

## Public SDK Testing Guidance

For public SDK tests, keep using the public API surface. Use ``Terra/agentic(name:id:_:)`` when the test covers a multi-step workflow, or bind individual operations with ``Terra/Operation/under(_:)`` when a child span must attach to a chosen parent.

```swift
import Terra
import OpenTelemetrySdk

let tracerProvider = TracerProviderBuilder().build()
Terra.install(.init(
  tracerProvider: tracerProvider,
  registerProvidersAsGlobal: false
))

let value = try await Terra.agentic(name: "planner-test", id: "issue-42") { agent in
  try await agent.tool(
    "search",
    callId: "call-1"
  ) { trace in
    trace.event("tool.test")
    return "stubbed"
  }
}
```

Public SDK consumers should keep using the canonical public factories and swap the installed tracer provider for deterministic tests.
Use the `TelemetryEngine` seam only when working inside the Terra package where `package` access is available.
