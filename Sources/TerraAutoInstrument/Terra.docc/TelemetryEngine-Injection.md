# TelemetryEngine Injection

Use ``Terra/TelemetryEngine`` when you need deterministic injection/mocking in tests or custom execution boundaries.

## Engine Protocol

The engine receives:

- ``Terra/TelemetryContext`` (operation, model/name, provider/runtime, capture policy)
- Precomputed call attributes
- A ``Terra/TraceHandle`` body closure

## Example

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

let result = try await Terra
  .tool("search", callID: Terra.ToolCallID("call-1"))
  .run(using: MockEngine()) { trace in
    trace.event("tool.mocked")
    return "stubbed-result"
  }
```

`run(using:)` keeps the canonical call construction unchanged while allowing controlled execution in tests.
