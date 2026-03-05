# Terra

@Metadata {
  @TechnologyRoot
}

OpenTelemetry-native observability for on-device GenAI workloads on Apple platforms.

Terra's canonical surface is task-oriented: build an operation with ``TerraCore/Terra/infer(_:prompt:provider:runtime:temperature:maxTokens:)``, ``TerraCore/Terra/stream(_:prompt:provider:runtime:temperature:maxTokens:expectedTokens:)``, ``TerraCore/Terra/embed(_:inputCount:provider:runtime:)``, ``TerraCore/Terra/agent(_:id:provider:runtime:)``, ``TerraCore/Terra/tool(_:callID:type:provider:runtime:)``, or ``TerraCore/Terra/safety(_:subject:provider:runtime:)``, then execute with ``TerraCore/Terra/Call/run(_:)``.

## Start Here

- New to Terra: <doc:Quickstart-90s>
- Want the complete canonical API map: <doc:Canonical-API>

## Learning Progression

- Beginner: <doc:Canonical-API>, <doc:Typed-IDs>
- Intermediate: <doc:Metadata-Builder>, <doc:TerraError-Model>
- Advanced: <doc:TelemetryEngine-Injection>

## Core Symbols

- ``TerraCore/Terra/start(_:)``
- ``TerraCore/Terra/shutdown()``
- ``TerraCore/Terra/Call``
- ``TerraCore/Terra/TraceHandle``

## Topics

### Quickstart

- <doc:Quickstart-90s>

### Beginner

- <doc:Canonical-API>
- <doc:Typed-IDs>

### Intermediate

- <doc:Metadata-Builder>
- <doc:TerraError-Model>

### Advanced

- <doc:TelemetryEngine-Injection>
