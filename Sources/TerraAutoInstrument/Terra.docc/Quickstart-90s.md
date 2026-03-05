# Quickstart (90s)

This path gets one traced call running with current canonical APIs.

## 1) Start Terra

```swift
import Terra

try await Terra.start(.init(preset: .quickstart))
```

## 2) Run One Instrumented Inference

```swift
import Terra

let userTierKey = Terra.TraceKey<String>("app.user_tier")

let answer = try await Terra
  .infer(
    Terra.ModelID("gpt-4o-mini"),
    prompt: "Give me a one-line status update.",
    provider: Terra.ProviderID("openai"),
    runtime: Terra.RuntimeID("http_api")
  )
  .metadata {
    Terra.event("infer.request")
    Terra.attr(.init("sample.kind"), "infer")
  }
  .run { trace in
    trace.attr(userTierKey, "free")
    trace.tokens(input: 32, output: 14)
    return "Status: all systems healthy."
  }
```

## 3) Shutdown Cleanly

```swift
await Terra.shutdown()
```

## What You Just Used

- Setup: ``TerraCore/Terra/start(_:)`` and ``TerraCore/Terra/shutdown()``
- Factory + execution: ``TerraCore/Terra/infer(_:prompt:provider:runtime:temperature:maxTokens:)`` and ``TerraCore/Terra/Call/run(_:)``
- Metadata APIs: ``TerraCore/Terra/event(_:)``, ``TerraCore/Terra/attr(_:_:)``, and ``TerraCore/Terra/Call/metadata(_:)``

For deeper patterns, continue with <doc:Canonical-API>.
