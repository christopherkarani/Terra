# CoreML Integration

Automatically trace CoreML model predictions without modifying your inference code.

## Overview

Terra's CoreML integration uses ObjectiveC method swizzling to intercept `MLModel.prediction(from:)` calls and automatically create inference spans. This works with any CoreML model without requiring manual instrumentation.

## MLModelConfiguration Setup

Configure your ``MLModelConfiguration`` to select compute units and enable debugging:

```swift
import CoreML
import Terra

let config = MLModelConfiguration()
config.computeUnits = .cpuAndGPU  // Default for most workloads
config.allowLowPrecisionAccumulationOnGPU = true
config.metalDevice = nil  // Use default GPU
```

### Compute Unit Selection

| Compute Units | Use Case |
|--------------|----------|
| ``MLComputeUnits/cpuOnly`` | Debugging, battery-critical |
| ``MLComputeUnits/gpuOnly`` | GPU-accelerated only |
| ``MLComputeUnits/cpuAndGPU`` | Balanced (default) |
| ``MLComputeUnits/all`` | CPU + GPU + Neural Engine |

```swift
// Maximum performance for large models
let performanceConfig = MLModelConfiguration()
performanceConfig.computeUnits = .all

// Battery-efficient for on-device models
let batteryConfig = MLModelConfiguration()
batteryConfig.computeUnits = .cpuAndGPU
```

## Auto-Instrumentation

CoreML auto-instrumentation is enabled by default when using Terra presets:

```swift
import Terra
import CoreML

// Terra.start() enables CoreML auto-instrumentation automatically
try await Terra.start(.init(preset: .production))

// Use CoreML normally — spans are created automatically
let model = try! MLModel(contentsOf: modelURL, configuration: config)
let input = try MLDictionaryFeatureProvider(dictionary: [:])
let prediction = try model.prediction(from: input)

// Spans include:
// - gen_ai.operation.name = "inference"
// - gen_ai.request.model = model identifier
// - gen_ai.provider.name = "on_device"
// - terra.runtime = "coreml"
// - terra.auto_instrumented = true
// - terra.coreml.compute_units = selected compute units
```

### Excluding Specific Models

Exclude models from tracing to reduce overhead on low-latency inference:

```swift
var config = Terra.Configuration(preset: .production)
config.features = [.coreML]

// CoreMLInstrumentation is controlled by Terra's feature flags
// To exclude specific models, use the CoreMLInstrumentation directly:
CoreMLInstrumentation.install(.init(
  enabled: true,
  excludedModels: ["low-latency-model", "streaming-model"]
))
```

## Metrics Collection

Collect deterministic runtime facts using ``Terra/Operation``:

```swift
import Terra
import CoreML

let result = try await Terra
  .infer(
    "coreml/com.yourorg.model@v3",
    runtime: Terra.RuntimeID("coreml"),
    provider: Terra.ProviderID("coreml")
  )
  .run { trace in
    trace.tag("terra.coreml.compute_units", "all")
    trace.tag("terra.coreml.model_version", "3.0")

    let config = MLModelConfiguration()
    config.computeUnits = .all

    let model = try MLModel(contentsOf: modelURL, configuration: config)
    let input = try MLDictionaryFeatureProvider(dictionary: [:])
    let prediction = try model.prediction(from: input)

    return "ok"
  }
```

## Manual Span Creation

For custom CoreML workflows, create spans manually. If one CoreML step must stay attached to a wider parent workflow, bind the inference operation with ``Terra/Operation/under(_:)`` or run it from ``Terra/agentic(name:id:_:)``.

```swift
import Terra
import CoreML

let parent = Terra.startSpan(name: "batch-import")
defer { parent.end() }

let result = try await Terra
  .infer(
    "coreml/custom-model",
    runtime: Terra.RuntimeID("coreml"),
    provider: Terra.ProviderID("coreml")
  )
  .under(parent)
  .run { trace in
    trace.tag("terra.coreml.compute_units", "cpuAndGPU")
    trace.tag("terra.coreml.batch_size", "1")
    trace.event("coreml.prediction.start")

    let model = try MLModel(contentsOf: modelURL)
    let output = try model.prediction(from: inputProvider)

    trace.event("coreml.prediction.complete")
    return output
  }
```

## Automatic Span Attributes

CoreML auto-instrumentation adds these attributes to spans:

| Attribute | Description |
|-----------|-------------|
| `terra.auto_instrumented` | Always `true` for swizzled spans |
| `gen_ai.operation.name` | `infer` |
| `gen_ai.request.model` | Model identifier |
| `gen_ai.provider.name` | `on_device` |
| `terra.runtime` | `coreml` |
| `terra.coreml.compute_units` | Selected compute units |

## See Also

- <doc:TerraCore> — Core concepts (privacy, lifecycle)
- <doc:FoundationModels> — Apple Foundation Models integration
- <doc:TelemetryEngine-Injection> — Testing with custom engines
