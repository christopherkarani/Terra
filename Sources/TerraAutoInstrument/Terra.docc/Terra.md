# ``Terra``

OpenTelemetry-native observability for on-device and remote GenAI workflows on Apple platforms.

Terra's public surface is workflow-first:

- start locally with ``Terra/quickStart()``
- inspect the API map with ``Terra/help()``
- validate setup with ``Terra/diagnose()``
- trace one request with ``Terra/workflow(name:id:_:)-swift.method``
- use ``Terra/workflow(name:id:messages:_:)-swift.method`` when transcript mutation belongs to the root workflow
- use ``Terra/SpanHandle/handoff()`` or ``Terra/SpanHandle/withToolParent(_:)`` when a later tool call must outlive a child inference/stream closure
- use ``Terra/startSpan(name:id:attributes:)`` only for explicit long-lived parent spans

## Start Here

- New to Terra: <doc:Quickstart-90s>
- Canonical API map: <doc:Canonical-API>
- Full reference: <doc:API-Reference>

## Core Symbols

- ``Terra/start(_:)``
- ``Terra/quickStart()``
- ``Terra/shutdown() async``
- ``Terra/help()``
- ``Terra/diagnose()``
- ``Terra/workflow(name:id:_:)-swift.method``
- ``Terra/workflow(name:id:messages:_:)-swift.method``
- ``Terra/startSpan(name:id:attributes:)``
- ``Terra/SpanHandle``
- ``Terra/SpanHandle/handoff()``
- ``Terra/SpanHandle/withToolParent(_:)``
- ``Terra/WorkflowTranscript``
- ``Terra/Operation``
- ``Terra/currentSpan()``
- ``Terra/activeSpans()``
- ``Terra/examples()``
- ``Terra/guides()``
- ``Terra/ask(_:)``
- ``Terra/playground()``

## Topics

### Quickstart

- <doc:Quickstart-90s>

### Core Docs

- <doc:Canonical-API>
- <doc:API-Reference>
- <doc:TerraError-Model>

### Platform Integrations

- <doc:Integrations>
- <doc:FoundationModels>
- <doc:CoreML-Integration>

### Advanced

- <doc:TelemetryEngine-Injection>
