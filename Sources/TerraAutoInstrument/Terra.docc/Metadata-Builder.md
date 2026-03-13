# Metadata Builder

Use ``Terra/TraceHandle`` methods inside ``Terra/Operation/run(_:)-swift.method`` to attach events and attributes to spans.

## Trace Annotations Inside run

```swift
import Terra

let includeDebug = true

_ = try await Terra
  .tool("search", callID: Terra.ToolCallID("call-1"), type: "web_search")
  .run { trace in
    trace.event("tool.invoked")
    trace.tag("tool.name", "search")

    if includeDebug {
      trace.tag("tool.debug", "true")
    }
    return ["result"]
  }
```

## Streaming with Incremental Updates

Inside ``Terra/Operation/run(_:)-swift.method``, annotate streaming progress directly on the trace:

```swift
import Terra

_ = try await Terra
  .stream(Terra.ModelID("gpt-4o-mini"), prompt: "Explain OTLP quickly")
  .run { trace in
    trace.event("stream.first_chunk")
    trace.tag("stream.chunk_index", "0")
    trace.chunk(8)
    trace.outputTokens(64)
    trace.firstToken()
    return "chunked-output"
  }
```

> Note: All values passed to ``Terra/TraceHandle/tag(_:_:)`` are stored as OpenTelemetry string attributes.
> For numeric aggregation (sums, percentiles) use ``Terra/TraceHandle/tokens(input:output:)`` instead.

Use <doc:TelemetryEngine-Injection> when you need deterministic test seams.
