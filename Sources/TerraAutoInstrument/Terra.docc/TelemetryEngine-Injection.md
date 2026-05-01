# Protocol Seams

These APIs are `package` scoped. They exist for Terra-internal tests and companion packages, not for general SDK consumption.

## Core Seam Types

- ``Terra/TelemetryEngine`` (`package`)
- ``Terra/TelemetryContext`` (`package`)
- ``Terra/SpanHandle`` (`public`)

The seam entry point is ``Terra/Operation/run(using:_:)`` (`package`).
Engine implementations handle ``Terra/TelemetryEngine/run(context:attributes:_:)`` and receive a ``Terra/SpanHandle`` for deterministic annotation behavior.

## Public SDK Testing Guidance

> Note: This article describes seams used by the Terra package itself. The
> `Terra.install(_:)` entry point referenced above is `package`-scoped, so
> downstream consumers cannot call it directly. Use the public
> ``Terra/Terra/start(_:)`` entry point instead — it configures Terra,
> registers tracer and meter providers, and returns once the SDK is running.

Public SDK tests should keep using the public workflow-first surface and let
``Terra/Terra/start(_:)`` install the providers. To assert on captured spans,
configure your application's `OpenTelemetry` tracer provider before calling
`Terra.start`, or use the `Terra.lockTestingIsolation()` and
`Terra.resetOpenTelemetryForTesting()` helpers from the Terra test target.

```swift
import Terra

try await Terra.start(.init(preset: .quickstart))

let value = try await Terra.workflow(name: "planner-test", id: "issue-42") { workflow in
  try await workflow.tool("search", callId: "call-1", type: "web_search") { span in
    span.event("tool.test")
    return "stubbed"
  }
}

await Terra.shutdown()
```

Use the `TelemetryEngine` seam only when working inside the Terra package where `package` access is available.
