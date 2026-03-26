# Metadata Builder

Use ``Terra/SpanHandle`` as the primary annotation surface inside ``Terra/trace(name:id:_:)-swift.method``, ``Terra/loop(name:id:messages:_:)``, and ``Terra/agentic(name:id:_:)``. ``Terra/TraceHandle`` remains the compatibility annotation surface inside ``Terra/Operation/run(_:)-swift.method``.

## Root Span Annotations

```swift
import Terra

let includeDebug = true

_ = try await Terra.trace(name: "tool.call", id: "call-1") { span in
  span.event("tool.invoked")
  span.attribute("tool.name", "search")

  if includeDebug {
    span.attribute("tool.debug", "true")
  }
  return ["result"]
}
```

## Streaming with Incremental Updates

Inside ``Terra/Operation/run(_:)-swift.method``, annotate streaming progress directly on the compatibility trace handle:

```swift
import Terra

_ = try await Terra
  .stream("gpt-4o-mini", prompt: "Explain OTLP quickly")
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

## Binding Work to an Explicit Parent

When child work starts outside the parent's immediate closure, bind it explicitly with ``Terra/Operation/under(_:)``:

```swift
import Terra

let parent = Terra.startSpan(name: "sync")
defer { parent.end() }

_ = try await Terra
  .tool("search", callId: "call-1")
  .under(parent)
  .run { trace in
    trace.event("tool.invoked")
    return ["result"]
  }
```

If the work must hop into a detached task, prefer ``Terra/SpanHandle/detached(priority:_:)`` or ``Terra/AgentHandle/detached(priority:_:)`` over raw `Task.detached`.
