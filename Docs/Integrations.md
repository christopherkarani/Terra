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

let request = Terra.InferenceRequest.chat(model: "coreml/com.yourorg.model@v3")

await Terra.inference(request).execute { trace in
  let config = MLModelConfiguration()
  config.computeUnits = .all
  trace
    .runtime("coreml")
    .attribute(.init("terra.coreml.compute_units"), "all")

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

let request = Terra.InferenceRequest.chat(model: "mlx/local/llama-3.2-1b")

await Terra.inference(request).execute { trace in
  trace
    .runtime("mlx")
    .attribute(.init("terra.mlx.device"), "gpu")
    .attribute(.init("terra.mlx.quantization"), "q4")

  // ... call into MLX
}
```

## Cardinality + Privacy Rules of Thumb

- Do **not** attach raw prompts, tool arguments, or model outputs as span attributes.
- Prefer numeric **metrics** (counts/latencies) over per-token/per-step span events.
- If you need content capture, use `Terra.Privacy` with `CaptureIntent.optIn` + redaction.

## See Also

- Persistence paths and storage configuration: `README.md`
- Instrumentation version access: `README.md`
- CI status badge and test commands: `README.md`
- Licensing: `README.md`
