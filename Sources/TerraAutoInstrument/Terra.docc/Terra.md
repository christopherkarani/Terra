# ``Terra``

OpenTelemetry-native observability for on-device GenAI workloads on Apple platforms.

Terra's canonical surface is trace-first: start locally with ``Terra/quickStart()``, inspect the API map with ``Terra/help()``, validate setup with ``Terra/diagnose()``, then instrument work with ``Terra/trace(name:id:_:)-swift.method`` for single-root tasks, ``Terra/loop(name:id:messages:_:)`` for mutable chat transcripts, ``Terra/agentic(name:id:_:)`` for multi-step agent workflows, and ``Terra/startSpan(name:id:attributes:)`` when lifecycle must be ended manually. The operation helpers such as ``Terra/infer(_:prompt:provider:runtime:temperature:maxTokens:)`` and ``Terra/stream(_:prompt:provider:runtime:temperature:maxTokens:expectedTokens:)`` remain available as secondary convenience APIs.

## Start Here

- New to Terra: <doc:Quickstart-90s>
- Want the complete canonical API map: <doc:Canonical-API>

## Learning Progression

- Beginner: <doc:Canonical-API>, <doc:Typed-IDs>
- Intermediate: <doc:Metadata-Builder>, <doc:TerraError-Model>, <doc:API-Reference>
- Advanced: <doc:TelemetryEngine-Injection>, <doc:Configuration-Reference>

## Core Symbols

- ``Terra/start(_:)``
- ``Terra/quickStart()``
- ``Terra/shutdown() async``
- ``Terra/help()``
- ``Terra/diagnose()``
- ``Terra/trace(name:id:_:)-swift.method``
- ``Terra/loop(name:id:messages:_:)``
- ``Terra/agentic(name:id:_:)``
- ``Terra/startSpan(name:id:attributes:)``
- ``Terra/SpanHandle``
- ``Terra/Operation``
- ``Terra/TraceHandle``
- ``Terra/capabilities()``
- ``Terra/guides()``
- ``Terra/examples()``
- ``Terra/ask(_:)``
- ``Terra/playground()``
- ``Terra/currentSpan()``

## Topics

### Quickstart

- <doc:Quickstart-90s>

### Beginner

- <doc:Canonical-API>
- <doc:Typed-IDs>

### Intermediate

- <doc:Metadata-Builder>
- <doc:TerraError-Model>
- <doc:API-Reference>
- <doc:Configuration-Reference>

### Reference

- <doc:API-Reference>
- <doc:Configuration-Reference>

### Advanced

- <doc:TelemetryEngine-Injection>

### Platform Integrations

- <doc:Integrations>
