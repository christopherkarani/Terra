# ``Terra``

OpenTelemetry-native observability for on-device GenAI workloads on Apple platforms.

Terra's canonical surface is task-oriented: build an operation with ``Terra/infer(_:prompt:provider:runtime:temperature:maxTokens:)``, ``Terra/stream(_:prompt:provider:runtime:temperature:maxTokens:expectedTokens:)``, ``Terra/embed(_:inputCount:provider:runtime:)``, ``Terra/agent(_:id:provider:runtime:)``, ``Terra/tool(_:callID:type:provider:runtime:)``, or ``Terra/safety(_:subject:provider:runtime:)``, then execute with ``Terra/Call/run(_:)``.

## Start Here

- New to Terra: <doc:Quickstart-90s>
- Want the complete canonical API map: <doc:Canonical-API>

## Learning Progression

- Beginner: <doc:Canonical-API>, <doc:Typed-IDs>
- Intermediate: <doc:Metadata-Builder>, <doc:TerraError-Model>, <doc:API-Reference>
- Advanced: <doc:TelemetryEngine-Injection>, <doc:Configuration-Reference>

## Core Symbols

- ``Terra/start(_:)``
- ``Terra/shutdown()``
- ``Terra/Call``
- ``Terra/TraceHandle``

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
