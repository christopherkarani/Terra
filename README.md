<p align="center">
  <img src="terra-banner.svg" alt="Terra Banner" width="100%" />
</p>

# Terra

Terra is a cross-platform GenAI observability SDK built on a Zig telemetry core with a stable C ABI.
Instrument inference, streaming, agents, tools, embeddings, and safety checks — from iPhones to drones to MCUs — with privacy-safe defaults and zero runtime dependencies.

```swift
import Terra

try await Terra.start()
let result = try await Terra.infer(Terra.ModelID("gpt-4o-mini"), prompt: "Say hello").run { "Hello" }
```

[![CI](https://github.com/christopherkarani/Terra/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/christopherkarani/Terra/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%20|%20macOS%20|%20visionOS-red.svg)]()

## Architecture

All language bindings share one native telemetry engine via a C ABI:

```
                           terra.h (C ABI)
                                │
                     ┌──────────┴──────────┐
                     │   libtera.a / .so   │
                     │   (Zig → native)    │
                     └──────────┬──────────┘
                                │
     ┌────────┬────────┬────────┼────────┬────────┬────────┐
     │        │        │        │        │        │        │
   Swift   Kotlin    Python    Rust     C++       C     (more)
     │        │        │        │        │        │
  CTerraBridge  JNI    ctypes  FFI   terra.hpp  direct
  OTel adapter  bridge  dlopen  safe  header-only  raw
  @TaskLocal  Coroutine ctx mgr  Drop  RAII     manual
```

| Language | Linkage | Wrapper | Memory Management |
|----------|---------|---------|-------------------|
| **C** | `#include "terra.h"` | None (raw API) | Manual `terra_shutdown()` |
| **C++** | `#include "terra.hpp"` | Header-only RAII | Destructor |
| **Swift** | CTerraBridge xcframework | OTel protocol adapter | `defer` in closures |
| **Kotlin** | JNI + `System.loadLibrary` | Kotlin SDK classes | `use {}` block |
| **Python** | `ctypes.cdll.LoadLibrary` | Pythonic classes | `with` context manager |
| **Rust** | `build.rs` links `libtera.a` | Safe wrappers | `Drop` trait |

**Key design decisions:**
- **Single source of truth** — 30+ functions defined once in Zig, exported via C ABI, wrapped by each language
- **Opaque handles** — `terra_t*` and `terra_span_t*` require no struct layout knowledge
- **Context is caller-owned** — no threadlocal in Zig; each language uses its native propagation (Swift `@TaskLocal`, Kotlin `CoroutineContext.Element`, etc.)
- **Cross-platform** — compiles for macOS, iOS, Linux x86/ARM, Android, freestanding MCUs (thumb, ARM)

### Platform Support

| Target | Transport | Status |
|--------|-----------|--------|
| macOS / iOS | OTLP/HTTP | Production |
| Android | OTLP/HTTP (OkHttp) | Production |
| Linux ARM (Pi, Jetson) | OTLP/HTTP | Production |
| Robotics (ROS 2) | ROS 2 topic + MQTT | Integration |
| Drones / Serial | UART (CRC16 framing) | Integration |
| MCUs (Cortex-M) | CoAP / Shared memory | Freestanding |

## Quick Start

Copy-ready snippets live in `Examples/Terra Sample/RecipeSnippets.swift` and compile as-is.

```swift
import Terra

try await Terra.start(.init(preset: .quickstart))
let answer = try await TerraRecipeSnippets.inferRecipe(prompt: userPrompt)
await Terra.shutdown()
```

### Python

```python
from terra import Terra, StatusCode

terra = Terra.init(service_name="my-app", service_version="1.0.0")

with terra.begin_inference_span(model="gpt-4") as span:
    span.set_int("gen_ai.request.max_tokens", 2048)
    span.set_double("gen_ai.request.temperature", 0.7)
    result = call_llm(prompt)
    span.set_int("gen_ai.usage.output_tokens", len(result))
    span.set_status(StatusCode.OK)

terra.shutdown()
```

### Rust

```rust
use terra::Terra;

let terra = Terra::init()?;
terra.set_service_info("my-app", "1.0.0")?;

terra.with_inference_span("gpt-4", None, false, |span| {
    span.set_int("gen_ai.request.max_tokens", 2048);
    span.set_double("gen_ai.request.temperature", 0.7);
    span.add_event("prompt_sent");
    Ok(())
})?;
// terra.shutdown() called automatically via Drop
```

### C++

```cpp
#include <terra.hpp>

auto terra = terra::Instance::init();
terra.set_service_info("my-app", "1.0.0");

{
    auto span = terra.begin_inference("gpt-4");
    span.set("gen_ai.request.max_tokens", int64_t(2048));
    span.set("gen_ai.request.temperature", 0.7);
    span.add_event("prompt_sent");
    // span.end() called automatically by destructor
}

// terra.shutdown() called automatically by destructor
```

### Kotlin

```kotlin
Terra.init(terraConfig { serviceName = "my-app"; serviceVersion = "1.0.0" })

Terra.beginInferenceSpan("gpt-4").use { span ->
    span.setAttribute("gen_ai.request.max_tokens", 2048L)
    span.setAttribute("gen_ai.request.temperature", 0.7)
    span.addEvent("prompt_sent")
}

Terra.shutdown()
```

### C

```c
#include "terra.h"

terra_t *inst = terra_init(NULL);
terra_set_service_info(inst, "my-app", "1.0.0");

terra_span_t *span = terra_begin_inference_span_ctx(inst, NULL, "gpt-4", false);
terra_span_set_int(span, "gen_ai.request.max_tokens", 2048);
terra_span_set_double(span, "gen_ai.request.temperature", 0.7);
terra_span_add_event(span, "prompt_sent");
terra_span_end(inst, span);

terra_shutdown(inst);
```

## Setup Presets

| Preset | Use when | Start call |
| --- | --- | --- |
| `quickstart` | Local dev defaults | `try await Terra.start()` |
| `production` | Persist traces and export in apps | `try await Terra.start(.init(preset: .production))` |
| `diagnostics` | Deep troubleshooting with extra telemetry | `try await Terra.start(.init(preset: .diagnostics))` |

## Span Types

| Span type | Factory | Example |
| --- | --- | --- |
| Inference | `Terra.infer(_:prompt:provider:runtime:temperature:maxTokens:)` | `try await Terra.infer(Terra.ModelID("gpt-4o-mini"), prompt: prompt).run { "ok" }` |
| Streaming | `Terra.stream(_:prompt:provider:runtime:temperature:maxTokens:expectedTokens:)` | `try await Terra.stream(Terra.ModelID("gpt-4o-mini")).run { trace in trace.chunk(tokens: 8); return "ok" }` |
| Agent | `Terra.agent(_:id:provider:runtime:)` | `try await Terra.agent("planner").run { "done" }` |
| Tool | `Terra.tool(_:callID:type:provider:runtime:)` | `try await Terra.tool("search", callID: Terra.ToolCallID()).run { "result" }` |
| Embedding | `Terra.embed(_:inputCount:provider:runtime:)` | `try await Terra.embed(Terra.ModelID("text-embedding-3-small"), inputCount: 3).run { vectors }` |
| Safety check | `Terra.safety(_:subject:provider:runtime:)` | `try await Terra.safety("toxicity", subject: text).run { true }` |

## Privacy Policies

| Policy | Behavior | Use when |
| --- | --- | --- |
| `.redacted` (default) | Captures telemetry metadata with HMAC-SHA256 redaction for content fields | Standard production default |
| `.lengthOnly` | Captures only content lengths (no raw content) | You need shape/size signals only |
| `.capturing` | Allows content capture when opted in per call | Controlled debugging environments |
| `.silent` | Drops content-related telemetry | Strictest privacy mode |

## Composable Call API

Use call composition when metadata is dynamic at runtime:

```swift
let result = try await Terra
  .infer(
    Terra.ModelID(modelName),
    prompt: prompt,
    provider: Terra.ProviderID(providerName),
    runtime: Terra.RuntimeID(runtimeName)
  )
  .capture(.includeContent)
  .attr(.init("app.user_tier"), userTier)
  .attr(.init("app.retry"), false)
  .run { trace in
    trace.responseModel(Terra.ModelID(modelName))
    trace.tokens(input: 128, output: 64)
    return try await llm.generate(prompt)
  }
```

Advanced seams/mocking patterns are documented in [`Docs/API_Cookbook.md`](Docs/API_Cookbook.md) and [`Docs/Front_Facing_API_Examples.md`](Docs/Front_Facing_API_Examples.md).

## Configuration Persistence

```swift
var config = Terra.Configuration(preset: .production)
config.persistence = .defaults()
try await Terra.start(config)
```

## Macros (`@Traced`)

```swift
import Terra
import TerraTracedMacro

@Traced(model: Terra.ModelID("gpt-4o-mini"))
func infer(prompt: String) async throws -> String { try await llm.generate(prompt) }

@Traced(model: Terra.ModelID("gpt-4o-mini"), streaming: true)
func stream(prompt: String) async throws -> String { try await llm.generate(prompt) }

@Traced(agent: "planner")
func agentStep() async throws -> String { "ok" }

@Traced(tool: "search")
func runTool(query: String) async throws -> String { "ok" }

@Traced(embedding: Terra.ModelID("text-embedding-3-small"))
func embed(text: String) async throws -> [Float] { [0.1, 0.2] }

@Traced(safety: "toxicity")
func safety(subject: String) async throws -> Bool { true }
```

## Foundation Models

```swift
#if canImport(FoundationModels)
import FoundationModels
import TerraFoundationModels

@available(macOS 26.0, iOS 26.0, *)
func runFoundationModels(prompt: String) async throws -> String {
  let session = Terra.TracedSession(model: .default)
  return try await session.respond(to: prompt)
}
#endif
```

## Advanced

- Full integrations: [`Docs/Integrations.md`](Docs/Integrations.md)
- Migration guide: [`Docs/Migration_Guide.md`](Docs/Migration_Guide.md)
- API cookbook: [`Docs/API_Cookbook.md`](Docs/API_Cookbook.md)
- Front-facing API reference: [`Docs/Front_Facing_API.md`](Docs/Front_Facing_API.md)
- Front-facing API examples: [`Docs/Front_Facing_API_Examples.md`](Docs/Front_Facing_API_Examples.md)
- Manual GitHub Pages + DocC publish: `Scripts/publish_pages_with_docc.sh`

## Installation

### Swift (SPM)

```swift
.package(url: "https://github.com/christopherkarani/Terra.git", from: "0.1.0")
```

Products: `Terra`, `TerraTracedMacro`, `TerraFoundationModels`, `TerraMLX`, `TerraLlama`

### Python

```bash
# Build the shared library first
cd zig-core && zig build
# Then use terra-python/terra.py (pip package coming soon)
export TERRA_LIB_PATH=./zig-core/zig-out/lib/libterra_shared.dylib
```

### Rust

```toml
# Cargo.toml
[dependencies]
terra = { path = "terra-rust" }  # crates.io publish coming soon
```

### C / C++

```bash
# Build libtera
cd zig-core && zig build
# Link: -I zig-core/include -L zig-core/zig-out/lib -lterra
# C++: also add -I terra-cpp/include for terra.hpp
```

### Android (Kotlin)

```bash
# Cross-compile native libs
./Scripts/build-libtera-android.sh
# Add terra-android/ as a module in your Gradle project
```

### Cross-compilation

```bash
cd zig-core
zig build -Dtarget=aarch64-linux-gnu        # Linux ARM (Pi, Jetson)
zig build -Dtarget=aarch64-linux-android     # Android
zig build -Dtarget=x86_64-linux-gnu          # Linux x86
zig build -Dtarget=thumb-freestanding-none -DTERRA_NO_STD=true  # MCU
```

## Requirements

- Swift: iOS 13+, macOS 14+, visionOS 1+, tvOS 13+, watchOS 6+
- Zig core: any platform Zig 0.14+ can target
- Python: 3.8+
- Rust: 2021 edition
- C++: C++17
- Android: minSdk 26, NDK or Zig cross-compile

License: Apache-2.0
