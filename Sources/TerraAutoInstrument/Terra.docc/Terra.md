# ``Terra``

@Metadata {
  @TechnologyRoot
}

OpenTelemetry-native observability for on-device GenAI workloads on Apple platforms.

## Overview

Use Terra to instrument inference, streaming, agents, tools, embeddings, and safety checks with privacy-safe defaults.

## Topics

### Getting Started

- <doc:Canonical-API>

### Advanced

- <doc:TelemetryEngine-Injection>

### Core Symbols

- ``Terra/start(_:)``
- ``Terra/shutdown()``
- ``Terra/infer(_:prompt:provider:runtime:temperature:maxTokens:)``
- ``Terra/stream(_:prompt:provider:runtime:temperature:maxTokens:expectedTokens:)``
- ``Terra/embed(_:inputCount:provider:runtime:)``
- ``Terra/agent(_:id:provider:runtime:)``
- ``Terra/tool(_:callID:type:provider:runtime:)``
- ``Terra/safety(_:subject:provider:runtime:)``
