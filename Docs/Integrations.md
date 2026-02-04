# Integrations (Core ML, MLX)

Terra intentionally keeps its **core API runtime-agnostic**: you instrument *your* inference/agent boundaries, and attach backend-specific metadata as **low-cardinality span attributes**.

## Core ML

If your app uses Core ML, attach what you *know deterministically* at runtime:

- Model identifier (your own stable string, e.g. `"coreml/com.yourorg.model@v3"`)
- Requested compute units (if you control the `MLModelConfiguration`)
- Input shape/batch size (only if low-cardinality)

Example:

```swift
import CoreML
import OpenTelemetryApi
import TerraCoreML
import Terra

let request = Terra.InferenceRequest(model: "coreml/com.yourorg.model@v3")

await Terra.withInferenceSpan(request) { scope in
  let config = MLModelConfiguration()
  config.computeUnits = .all
  scope.setCoreMLAttributes(configuration: config)

  // ... call into Core ML
}
```

## MLX

MLX (and MLX-based LLM stacks) typically expose runtime details like device placement and dtype/quantization. Capture only **bounded-cardinality** values:

- Device: `"cpu"` / `"gpu"` (or your own normalized labels)
- Dtype / quantization: `"fp16"` / `"int8"` / `"q4"` etc
- Batch size (if bounded)

Example:

```swift
import OpenTelemetryApi
import Terra

let request = Terra.InferenceRequest(model: "mlx/local/llama-3.2-1b")

await Terra.withInferenceSpan(request) { scope in
  scope.setAttributes([
    "terra.runtime": .string("mlx"),
    "terra.mlx.device": .string("gpu"),
    "terra.mlx.quantization": .string("q4"),
  ])

  // ... call into MLX
}
```

## Cardinality + Privacy Rules of Thumb

- Do **not** attach raw prompts, tool arguments, or model outputs as span attributes.
- Prefer numeric **metrics** (counts/latencies) over per-token/per-step span events.
- If you need content capture, use `Terra.Privacy` with `CaptureIntent.optIn` + redaction.
