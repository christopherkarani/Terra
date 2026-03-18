# Integrations (Core ML, MLX)

Terra keeps its core API runtime-agnostic. You instrument your boundaries and attach backend metadata as low-cardinality attributes.

## Core ML

Capture deterministic runtime facts:

- model identifier (stable string)
- compute units (`cpuAndGPU`, `all`, etc.)
- bounded input shape/batch metadata

```swift
import CoreML
import TerraCoreML
import Terra

let result = await Terra
  .infer(
    Terra.ModelID("coreml/com.yourorg.model@v3"),
    runtime: Terra.RuntimeID("coreml"),
    provider: Terra.ProviderID("coreml")
  )
  .attr(.init("terra.coreml.compute_units"), "all")
  .run {
    let config = MLModelConfiguration()
    config.computeUnits = .all
    // call Core ML here
    return "ok"
  }

_ = result
```

## MLX

Capture bounded runtime labels:

- device: `cpu`, `gpu`, `ane`
- quantization/dtype: `q4`, `fp16`, etc.
- bounded batch size

```swift
import Terra

let result = await Terra
  .infer(
    Terra.ModelID("mlx/local/llama-3.2-1b"),
    runtime: Terra.RuntimeID("mlx"),
    provider: Terra.ProviderID("mlx")
  )
  .attr(.init("terra.mlx.device"), "gpu")
  .attr(.init("terra.mlx.quantization"), "q4")
  .run {
    // call MLX here
    return "ok"
  }

_ = result
```

## Cardinality + Privacy Rules

- Do not attach raw prompts/tool args/model outputs as attributes.
- Prefer counts/latencies and bounded labels.
- For content capture on specific calls, use `.capture(.includeContent)`.
