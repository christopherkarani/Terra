# Protocol Seams

Use ``TerraCore/Terra/TelemetryEngine`` to inject deterministic execution for tests or custom runtimes.

## Core Seam Types

- ``TerraCore/Terra/TelemetryEngine``
- ``TerraCore/Terra/TelemetryContext``
- ``TerraCore/Terra/TraceHandle``

The seam entry point is ``TerraCore/Terra/Call/run(using:_:)``.
Engine implementers handle ``TerraCore/Terra/TelemetryEngine/run(context:attributes:_:)``.

## Minimal Mock Engine

```swift
import Terra

struct MockEngine: Terra.TelemetryEngine {
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

let value = try await Terra
  .tool("search", callID: Terra.ToolCallID("call-1"))
  .run(using: MockEngine()) { trace in
    trace.event("tool.mocked")
    return "stubbed"
  }
```

This keeps canonical call construction unchanged while swapping execution behavior.
