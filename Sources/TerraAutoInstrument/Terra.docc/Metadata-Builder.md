# Metadata Builder

Use ``Terra/Call/metadata(_:)`` to build structured events and attributes with ``Terra/MetadataBuilder``.

## Call-Level Metadata

```swift
import Terra

let includeDebug = true

_ = try await Terra
  .tool("search", callID: Terra.ToolCallID("call-1"), type: "web_search")
  .metadata {
    Terra.event("tool.invoked")
    Terra.attr(.init("tool.name"), "search")

    if includeDebug {
      Terra.attr(.init("tool.debug"), true)
    }
  }
  .run { ["result"] }
```

## Trace-Level Metadata

Inside ``Terra/Call/run(_:)``, use ``Terra/TraceHandle/metadata(_:)`` for incremental updates:

```swift
import Terra

_ = try await Terra
  .stream(Terra.ModelID("gpt-4o-mini"), prompt: "Explain OTLP quickly")
  .run { trace in
    trace.metadata {
      Terra.event("stream.first_chunk")
      Terra.attr(.init("stream.chunk_index"), 0)
    }
    trace.chunk(8)
    trace.outputTokens(64)
    trace.firstToken()
    return "chunked-output"
  }
```

Use <doc:TelemetryEngine-Injection> when you need deterministic test seams.
