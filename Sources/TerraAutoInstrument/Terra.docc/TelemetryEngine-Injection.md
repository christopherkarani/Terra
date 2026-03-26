# Protocol Seams

These APIs are `package` scoped. They exist for Terra-internal tests and companion packages, not for general SDK consumption.

## Core Seam Types

- ``Terra/TelemetryEngine`` (`package`)
- ``Terra/TelemetryContext`` (`package`)
- ``Terra/SpanHandle`` (`public`)

The seam entry point is ``Terra/Operation/run(using:_:)`` (`package`).
Engine implementations handle ``Terra/TelemetryEngine/run(context:attributes:_:)`` and receive a ``Terra/SpanHandle`` for deterministic annotation behavior.

## Public SDK Testing Guidance

Public SDK tests should keep using the public workflow-first surface and swap the installed tracer provider for deterministic assertions.

```swift
import Terra
import OpenTelemetrySdk

let tracerProvider = TracerProviderBuilder().build()
Terra.install(.init(
  tracerProvider: tracerProvider,
  registerProvidersAsGlobal: false
))

let value = try await Terra.workflow(name: "planner-test", id: "issue-42") { workflow in
  try await workflow.tool("search", callId: "call-1") { span in
    span.event("tool.test")
    return "stubbed"
  }
}
```

Use the `TelemetryEngine` seam only when working inside the Terra package where `package` access is available.
