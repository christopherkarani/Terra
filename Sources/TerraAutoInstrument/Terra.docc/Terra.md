# ``Terra``

OpenTelemetry-native observability for on-device GenAI workloads on Apple platforms.

Terra's canonical surface is task-oriented: build an operation with ``Terra/infer(_:prompt:provider:runtime:temperature:maxTokens:)``, ``Terra/stream(_:prompt:provider:runtime:temperature:maxTokens:expectedTokens:)``, ``Terra/embed(_:inputCount:provider:runtime:)``, ``Terra/agent(_:id:provider:runtime:)``, ``Terra/tool(_:callId:type:provider:runtime:)``, or ``Terra/safety(_:subject:provider:runtime:)``, then execute with ``Terra/Operation/run(_:)-swift.method``. For multi-step loops that need one root span across model calls, tools, and detached tasks, prefer ``Terra/agentic(name:id:_:)``.

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
- ``Terra/diagnose()``
- ``Terra/Operation``
- ``Terra/TraceHandle``
- ``Terra/SpanHandle``
- ``Terra/capabilities()``
- ``Terra/guides()``
- ``Terra/examples()``
- ``Terra/ask(_:)``
- ``Terra/currentSpan()``
- ``Terra/agentic(name:id:_:)``
- ``Terra/startSpan(name:id:attributes:)``
- ``Terra/trace(name:id:_:)-swift.method``

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
