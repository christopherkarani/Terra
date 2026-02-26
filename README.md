<p align="center">
  <img src="terra-banner.svg" alt="Terra Banner" width="100%" />
</p>

# Terra 🌍

**Stop flying blind with your local AI.**

Terra is a privacy-first observability layer for on-device GenAI. Built on OpenTelemetry, it gives you production-grade tracing for model inference, embeddings, and agents—with zero-code setup.

[![CI](https://github.com/christopherkarani/Terra/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/christopherkarani/Terra/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%20|%20macOS%20|%20visionOS-red.svg)]()
[![Website](https://img.shields.io/badge/Website-terra.dev-cyan.svg)](website/)

---

### Why Terra?
- **🔌 Zero-Code Auto-Instrumentation**: Capture CoreML and HTTP AI calls (OpenAI, Anthropic, etc.) with a single line of code.
- **🔒 Privacy First**: Content policy is `.never` by default. No raw prompts leave the device without explicit opt-in.
- **⚡️ Built for Performance**: Lightweight Signpost integration, on-device persistence, and OTLP/HTTP export.
- **🧩 Multi-Runtime**: Native support for **CoreML**, **MLX**, **Llama.cpp**, and **Apple Foundation Models**.

---

### Quickstart

#### 1. Add via SwiftPM
```swift
.package(url: "https://github.com/christopherkarani/Terra.git", from: "0.1.0")
```

#### 2. Start Auto-Instrumentation
```swift
import Terra

try Terra.start(preset: .quickstart)
```

That's it. Every CoreML prediction and HTTP request to known AI APIs now produces OpenTelemetry spans.

---

### Deep Instrumentation

#### Manual Spans
```swift
try await Terra.withInferenceSpan(model: "llama-3.2") { scope in
    let result = try await model.generate(prompt)
    scope.setAttributes(["tokens": result.count])
}
```

For expert users, you can pass the full request model and attach additional attributes:
```swift
let request = Terra.InferenceRequest(
  model: "llama-3.2",
  prompt: promptText,
  promptCapture: .optIn,
  maxOutputTokens: 256,
  temperature: 0.2,
)

try await Terra.withInferenceSpan(request) { scope in
  scope.setAttributes([
    "gen_ai.provider.name": .string("openai-compatible"),
    "terra.runtime": .string("custom_runtime")
  ])
  let result = try await model.generate()
}
```

#### Swift Macros
```swift
import TerraTracedMacro

@Traced(model: "whisper-large")
func transcribe(audio: Data) async throws -> String { 
    // Body is automatically wrapped in an inference span
}
```

#### Specialty Runtimes
```swift
// MLX
try await TerraMLX.traced(model: "mlx-community/Llama-3.2-1B") {
    try await model.generate(prompt)
}

// Llama.cpp
try await TerraLlama.traced(model: "llama-3.2-1b") { streamScope in
    // custom streaming logic
}
```

---

### Modules

| Module | Purpose |
| :--- | :--- |
| `Terra` | **Entry point**. Auto-instruments CoreML + HTTP. |
| `TerraCore` | Core API & OpenTelemetry runtime. |
| `TerraMLX` | Tracing for Swift MLX. |
| `TerraLlama` | Tracing for Llama.cpp / Llama-based models. |
| `TerraTraceKit` | Reusable trace decoding & modeling for custom UIs. |

---

**Requirements**: iOS 13+, macOS 14+, tvOS 13+, watchOS 6+, visionOS 1+.
**License**: Apache-2.0
