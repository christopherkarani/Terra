# Quickstart (90s)

This path gets one traced workflow running with Terra's current primary APIs.

## 1) Start Terra

Initialize once with ``Terra/quickStart()`` for the most explicit local-development setup, or use ``Terra/start(_:)`` if you want preset-driven configuration.

```swift
import Terra

try await Terra.quickStart()
```

## 2) Discover The Primary APIs

```swift
import Terra

print(Terra.help())
let report = Terra.diagnose()
print(report.summary)
```

## 3) Run One Root Span

```swift
import Terra

let answer = try await Terra.trace(name: "status.update", id: "demo-1") { span in
  span.event("infer.request")
  span.attribute("sample.kind", "infer")
  span.attribute("app.user_tier", "free")
  span.tokens(input: 32, output: 14)
  span.responseModel("gpt-4o-mini")
  return "Status: all systems healthy."
}
```

## 4) Shutdown Cleanly

Flush and teardown with ``Terra/shutdown()``.

```swift
await Terra.shutdown()
```

## What You Just Used

- Setup: ``Terra/start(_:)`` and ``Terra/shutdown()``
- Discovery: ``Terra/help()`` and ``Terra/diagnose()``
- Primary tracing: ``Terra/trace(name:id:_:)-swift.method``
- Root-span annotations: ``Terra/SpanHandle/event(_:)``, ``Terra/SpanHandle/tokens(input:output:)``, ``Terra/SpanHandle/responseModel(_:)``

If your workflow owns a mutable transcript, continue with ``Terra/loop(name:id:messages:_:)``. If it alternates between inference and tools under one long-lived root, continue with ``Terra/agentic(name:id:_:)``.

For deeper patterns, continue with <doc:Canonical-API>.
