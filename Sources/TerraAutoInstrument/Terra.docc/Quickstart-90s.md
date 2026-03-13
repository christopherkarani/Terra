# Quickstart (90s)

This path gets one traced call running with current canonical APIs.

## 1) Start Terra

Initialize once with ``Terra/start(_:)``.

```swift
import Terra

try await Terra.start(.init(preset: .quickstart))
```

## 2) Run One Instrumented Inference

```swift
import Terra

let answer = try await Terra
  .infer(
    Terra.ModelID("gpt-4o-mini"),
    prompt: "Give me a one-line status update.",
    provider: Terra.ProviderID("openai"),
    runtime: Terra.RuntimeID("http_api")
  )
  .run { trace in
    trace.event("infer.request")
    trace.tag("sample.kind", "infer")
    trace.tag("app.user_tier", "free")
    trace.tokens(input: 32, output: 14)
    return "Status: all systems healthy."
  }
```

## 3) Shutdown Cleanly

Flush and teardown with ``Terra/shutdown()``.

```swift
await Terra.shutdown()
```

## What You Just Used

- Setup: ``Terra/start(_:)`` and ``Terra/shutdown()``
- Factory + execution: ``Terra/infer(_:prompt:provider:runtime:temperature:maxTokens:)`` and ``Terra/Operation/run(_:)-swift.method``
- Trace annotations: ``Terra/TraceHandle/event(_:)``, ``Terra/TraceHandle/tag(_:_:)``, ``Terra/TraceHandle/tokens(input:output:)``

For deeper patterns, continue with <doc:Canonical-API>.
