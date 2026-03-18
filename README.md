<p align="center">
  <img src="terra-banner.svg" alt="Terra" width="100%" />
</p>

<p align="center">
  <strong>GenAI observability from iPhones to drones. One engine, six languages, zero cloud dependency.</strong>
</p>

<p align="center">
  <a href="https://github.com/christopherkarani/Terra/actions/workflows/ci.yml"><img src="https://github.com/christopherkarani/Terra/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" alt="License" /></a>
  <img src="https://img.shields.io/badge/Swift-5.9+-orange.svg" alt="Swift 5.9+" />
  <img src="https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20Android%20%7C%20Linux%20%7C%20visionOS%20%7C%20MCU-red.svg" alt="Platforms" />
</p>

---

Terra instruments model inference, streaming, agents, tool calls, embeddings, and safety checks — with privacy-safe defaults and no runtime dependencies. A single Zig telemetry core powers native SDKs in Swift, Python, Rust, Kotlin, C++, and C.

```swift
import Terra

try await Terra.start()
// CoreML predictions and HTTP AI calls are now automatically traced.
```

## Why Terra?

- **Privacy by default.** Content is never captured unless you opt in. Redaction happens at collection time via HMAC-SHA256 — not in transit, not in a pipeline you don't control.
- **One engine, six languages.** A single Zig core (5,600 LOC, 121 tests) exports a stable C ABI. Each language wraps it idiomatically — no reimplementation drift.
- **Auto-instrumentation, zero code changes.** CoreML predictions traced via runtime swizzling. HTTP calls to OpenAI, Anthropic, Google, and 5 more providers detected automatically.
- **GenAI-native spans.** Built-in span types for inference, streaming (TTFT, tokens/sec, stall detection), agents, tools, embeddings, and safety checks. Not generic web traces retrofitted.
- **On-device first.** Works offline. Persists locally. Exports via OTLP when you're ready — or never.

## Installation

### Swift (SPM)

```swift
dependencies: [
    .package(url: "https://github.com/christopherkarani/Terra.git", from: "0.1.0")
]
```

Products: `Terra` (umbrella), `TerraTracedMacro`, `TerraFoundationModels`, `TerraMLX`, `TerraLlama`

### Other languages

```bash
# Build the Zig core (required for all non-Swift bindings)
cd zig-core && zig build
```

| Language | Install |
|----------|---------|
| **Python** | `export TERRA_LIB_PATH=./zig-core/zig-out/lib/libterra_shared.dylib` then `import terra` |
| **Rust** | `terra = { path = "terra-rust" }` in Cargo.toml |
| **C++** | Link `-lterra` and `#include <terra.hpp>` (header-only RAII) |
| **Kotlin** | `./Scripts/build-libtera-android.sh`, add `terra-android/` module |
| **C** | Link `-lterra` and `#include "terra.h"` |

<details>
<summary>Cross-compilation targets</summary>

```bash
cd zig-core
zig build -Dtarget=aarch64-linux-gnu        # Linux ARM (Pi, Jetson)
zig build -Dtarget=aarch64-linux-android     # Android
zig build -Dtarget=x86_64-linux-gnu          # Linux x86
zig build -Dtarget=thumb-freestanding-none -DTERRA_NO_STD=true  # MCU
```

</details>

## Quick Start

### Swift

One line for the common case — auto-instruments CoreML and HTTP AI calls:

```swift
try await Terra.start()
```

Need manual spans? Use the composable API:

```swift
let answer = try await Terra
    .infer(Terra.ModelID("gpt-4o-mini"), prompt: userPrompt)
    .run { trace in
        trace.tokens(input: 128, output: 64)
        return try await llm.generate(userPrompt)
    }
```

Or annotate functions directly with `@Traced`:

```swift
@Traced(model: Terra.ModelID("gpt-4o-mini"))
func generate(prompt: String) async throws -> String {
    try await llm.generate(prompt)
}
```

### Python

```python
from terra import Terra, StatusCode

terra = Terra.init(service_name="my-app", service_version="1.0.0")

with terra.begin_inference_span(model="gpt-4") as span:
    span.set_int("gen_ai.request.max_tokens", 2048)
    result = call_llm(prompt)
    span.set_status(StatusCode.OK)

terra.shutdown()
```

### Rust

```rust
use terra::Terra;

let terra = Terra::init()?;
terra.with_inference_span("gpt-4", None, false, |span| {
    span.set_int("gen_ai.request.max_tokens", 2048);
    span.add_event("prompt_sent");
    Ok(())
})?;
// shutdown called automatically via Drop
```

<details>
<summary>C++, Kotlin, and C examples</summary>

**C++**
```cpp
#include <terra.hpp>

auto terra = terra::Instance::init();
{
    auto span = terra.begin_inference("gpt-4");
    span.set("gen_ai.request.max_tokens", int64_t(2048));
    // span.end() called by destructor
}
// terra.shutdown() called by destructor
```

**Kotlin**
```kotlin
Terra.init(terraConfig { serviceName = "my-app"; serviceVersion = "1.0.0" })
Terra.beginInferenceSpan("gpt-4").use { span ->
    span.setAttribute("gen_ai.request.max_tokens", 2048L)
    span.addEvent("prompt_sent")
}
Terra.shutdown()
```

**C**
```c
terra_t *inst = terra_init(NULL);
terra_span_t *span = terra_begin_inference_span_ctx(inst, NULL, "gpt-4", false);
terra_span_set_int(span, "gen_ai.request.max_tokens", 2048);
terra_span_end(inst, span);
terra_shutdown(inst);
```

</details>

## Architecture

Every language binding wraps the same native telemetry engine:

```
                         terra.h (stable C ABI)
                              │
                   ┌──────────┴──────────┐
                   │   libtera.a / .so   │
                   │     (Zig core)      │
                   └──────────┬──────────┘
                              │
   ┌────────┬────────┬────────┼────────┬────────┬────────┐
 Swift   Kotlin   Python    Rust     C++       C     (more)
```

30+ functions defined once in Zig, exported via C ABI, wrapped idiomatically per language. No threadlocals — each language uses its native context propagation (Swift `@TaskLocal`, Kotlin `CoroutineContext`, Python context managers, Rust `Drop`).

### Platform support

| Target | Transport | Status |
|--------|-----------|--------|
| macOS / iOS | OTLP/HTTP | Production |
| Android | OTLP/HTTP (OkHttp) | Production |
| Linux ARM (Pi, Jetson) | OTLP/HTTP | Production |
| Robotics (ROS 2) | ROS 2 topic + MQTT | Integration |
| Drones / Serial | UART (CRC16 framing) | Integration |
| MCUs (Cortex-M) | CoAP / Shared memory | Freestanding |

## Span Types

Six GenAI-specific span types, each with typed scopes for compile-time safety:

| Span | Swift API | What it captures |
|------|-----------|-----------------|
| **Inference** | `Terra.infer(model, prompt:)` | Model, tokens, latency, provider |
| **Streaming** | `Terra.stream(model)` | TTFT, tokens/sec, chunk count, stalls |
| **Agent** | `Terra.agent(name)` | Agent steps, nested tool calls |
| **Tool** | `Terra.tool(name, callID:)` | Execution time, input/output |
| **Embedding** | `Terra.embed(model, inputCount:)` | Vector dimensions, batch size |
| **Safety** | `Terra.safety(name, subject:)` | Check result, latency |

## Privacy

Privacy is architecture, not configuration. Content redaction happens at the point of collection.

| Policy | What happens |
|--------|-------------|
| `.redacted` (default) | Metadata captured; content fields HMAC-SHA256 hashed |
| `.lengthOnly` | Only content lengths — no text at all |
| `.capturing` | Full content when opted in per call |
| `.silent` | Content telemetry dropped entirely |

## Configuration

Three presets cover most cases:

```swift
try await Terra.start()                                    // quickstart (local dev)
try await Terra.start(.init(preset: .production))          // persist + export
try await Terra.start(.init(preset: .diagnostics))         // full profiling
```

Fine-tune with the configuration builder — privacy, export destination, persistence strategy, CoreML/HTTP/session features, and memory/GPU profiling are all independently configurable. See [API Cookbook](Docs/API_Cookbook.md) for details.

## Requirements

| Platform | Minimum |
|----------|---------|
| iOS | 13.0+ |
| macOS | 14.0+ |
| visionOS | 1.0+ |
| tvOS | 13.0+ |
| watchOS | 6.0+ |
| Swift | 5.9+ |
| Zig core | Any target Zig 0.14+ supports |
| Python | 3.8+ |
| Rust | 2021 edition |
| C++ | C++17 |
| Android | minSdk 26 |

## Documentation

- [API Reference](Docs/api-reference.md) — full public surface
- [Cookbook](Docs/cookbook.md) — recipes, mocking, advanced patterns
- [Integrations](Docs/integrations.md) — CoreML, FoundationModels, MLX, llama.cpp
- [Migration](Docs/migration.md) — upgrading between versions

## Contributing

Contributions welcome. See [GitHub Issues](https://github.com/christopherkarani/Terra/issues) for open work.

```bash
swift build && swift test        # Build + run all tests
swift test --filter TerraTests   # Run a specific target
```

## License

Released under the [Apache 2.0 License](LICENSE).
