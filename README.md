<p align="center">
  <img src="docs/terra-banner.png" alt="Terra" width="100%" />
</p>

<h3 align="center">On-device GenAI observability for Swift</h3>

<p align="center">
  One line of code. Every model call traced.<br/>
  Privacy-first. OpenTelemetry-native. Built for Apple platforms.
</p>

<p align="center">
  <a href="https://github.com/christopherkarani/Terra/actions/workflows/ci.yml?query=branch%3Amain"><img src="https://github.com/christopherkarani/Terra/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI" /></a>
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-5.9+-F05138.svg?style=flat&logo=swift&logoColor=white" alt="Swift 5.9+" /></a>
  <a href="#platform-support"><img src="https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20visionOS-blue.svg?style=flat" alt="Platforms" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-green.svg?style=flat" alt="License" /></a>
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> &middot;
  <a href="#how-it-works">How It Works</a> &middot;
  <a href="#features">Features</a> &middot;
  <a href="docs/TERRA_FEATURES.md">Full Docs</a> &middot;
  <a href="#trace-viewer">Trace Viewer</a>
</p>

---

## The Problem

You're running ML models on-device — CoreML, MLX, Ollama, llama.cpp, Apple Foundation Models. Something is slow. A model loads in 3 seconds on one device, 12 on another. Streaming stalls. Token throughput drops. You have no idea why because **there are no tools for on-device AI observability**.

Terra fixes this.

## Quick Start

### Install

```swift
// Package.swift
dependencies: [
  .package(url: "https://github.com/christopherkarani/Terra.git", branch: "main")
]
```

### Zero-code instrumentation

```swift
import Terra

try Terra.start()
```

That's it. Every CoreML prediction and HTTP AI API call is now traced — model name, latency, token counts, memory delta, GPU time, streaming metrics — all captured automatically with zero changes to your app code.

### See your traces

```bash
# Terminal — live trace viewer
swift run terra trace serve

# Or launch the native macOS app
swift build --target TraceMacApp && open .build/arm64-apple-macosx/debug/TraceMacApp
```

## How It Works

Terra wraps your AI operations in [OpenTelemetry](https://opentelemetry.io) spans with rich, structured metadata. No prompts or completions are captured — only performance telemetry.

```
┌─────────────────────────────────────────────────────┐
│  Your App                                           │
│                                                     │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐            │
│  │  CoreML   │ │  Ollama  │ │   MLX    │  ...       │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘            │
│       └─────────────┼───────────┘                   │
│                     ▼                               │
│              ┌─────────────┐                        │
│              │    Terra    │  auto-instrumentation   │
│              └──────┬──────┘                        │
│                     ▼                               │
│          ┌──────────────────┐                       │
│          │  OpenTelemetry   │                       │
│          └────────┬─────────┘                       │
│                   │                                 │
└───────────────────┼─────────────────────────────────┘
                    ▼
    ┌───────────────────────────────┐
    │  OTLP/HTTP  │  Disk  │  CLI  │
    └───────────────────────────────┘
```

## Three Integration Tiers

Choose your level of control:

```swift
// Tier 1 — Zero-code (auto-instruments CoreML + HTTP AI APIs)
try Terra.start()

// Tier 2 — One annotation
@Traced(model: "llama-3.2-1B")
func summarize(prompt: String) async throws -> String { ... }

// Tier 3 — Full control
try await Terra.withInferenceSpan(.init(model: "llama-3.2-1B")) { scope in
    let result = try await model.generate(prompt)
    scope.addEvent("generation.complete")
    return result
}
```

## 8 Runtimes, One SDK

| Runtime | Integration | What's captured |
|---|---|---|
| **CoreML** | Auto (swizzling) | Compute units, model name, memory delta, GPU time |
| **Foundation Models** | `TracedSession` wrapper | Token counts via reflection, TTFT, streaming TPS |
| **MLX** | `TerraMLX.traced {}` | Device, memory footprint, model load time |
| **llama.cpp** | C bridge callbacks | Per-token decode latency, logprob, KV cache, stages |
| **Ollama** | Auto (HTTP) | Request/response parsing, streaming SSE, stall detection |
| **LM Studio** | Auto (HTTP) | Same as Ollama, auto-detected by port |
| **OpenAI / Anthropic / Google** | Auto (HTTP) | Model, tokens, temperature, streaming TTFT/TPS |
| **OpenClaw** | Gateway + diagnostics | Dual-path proxy instrumentation |

## Features

### Streaming Intelligence

```swift
try await Terra.withStreamingInferenceSpan(request) { stream in
    for try await token in myStream {
        stream.recordToken()  // TTFT, TPS, stall detection — all automatic
    }
}
```

Captures time-to-first-token, tokens/sec, chunk counts, and detects stalls (>300ms gaps) in real-time.

### Privacy-First by Default

```swift
// Default: content policy is .never — no prompts or completions are captured
Terra.install(.init(privacy: .default))

// Opt-in when needed, with HMAC-SHA256 anonymization
Terra.install(.init(privacy: .init(
    contentPolicy: .optIn,
    redaction: .hashSHA256,
    anonymization: .init(rotationWindow: .hours(24))
)))
```

- Content capture is **off** by default
- SHA-256 redaction with rotating HMAC keys
- Per-request opt-in granularity
- Export control: allowlist runtimes, block telemetry from unapproved models
- Audit logging for compliance

### Hardware Profiling

```swift
try Terra.start(.init(
    profiling: .init(
        enableMemoryProfiler: true,   // RSS delta, peak memory via Mach APIs
        enableMetalProfiler: true     // GPU utilization, VRAM, compute time
    )
))
```

Track memory impact, GPU utilization, thermal state, and thread count alongside your model telemetry.

### Built-in Recommendations

Terra surfaces actionable suggestions based on observed telemetry patterns:

- **Thermal slowdown** — device is throttling, consider smaller model
- **Prompt cache miss** — cache miss impacting latency
- **Model swap regression** — performance degraded after model change
- **Stalled token** — generation stall detected with gap duration

Configurable confidence thresholds, cooldowns, and dedup windows.

### 5 OTel Metrics Out of the Box

| Metric | Type |
|---|---|
| `terra.inference.count` | Counter |
| `terra.inference.duration_ms` | Histogram |
| `terra.recommendation.count` | Counter |
| `terra.anomaly.count` | Counter |
| `terra.stall.count` | Counter |

## Trace Viewer

A native macOS app for exploring traces produced by Terra.

**Three-column layout:**
- **Trace list** — filter by runtime, search, sort by duration or time
- **Timeline / Tree** — Canvas-based lane visualization or hierarchical span tree
- **Inspector** — Attributes, classified events, links, raw JSON

**Live mode** — receives OTLP/HTTP on port 4318 for real-time trace ingestion from devices and simulators.

```bash
swift build --target TraceMacApp && open .build/arm64-apple-macosx/debug/TraceMacApp
```

## CLI

```bash
# Live trace receiver with real-time rendering
swift run terra trace serve

# Tree format with filtering
swift run terra trace serve --format tree --filter name=terra.inference

# Diagnostic checklist
swift run terra trace doctor
```

## Enterprise Ready

- **OTLP/HTTP export** — plug into Datadog, Honeycomb, Grafana, or any OTel collector
- **On-device persistence** — offline buffering with automatic replay
- **Session tracking** — cross-span session context with continuity analysis
- **Compliance** — export controls, retention policies, audit logging
- **Provider strategies** — `registerNew` for greenfield, `augmentExisting` for brownfield
- **Instruments.app** — signpost integration for native Apple profiling

## Modules

| Module | Purpose |
|---|---|
| `Terra` | Umbrella — auto-instrumentation, one `Terra.start()` call |
| `TerraCore` | Core SDK — spans, privacy, compliance, metrics |
| `TerraCoreML` | CoreML auto-instrumentation via swizzling |
| `TerraHTTPInstrument` | HTTP AI API auto-instrumentation |
| `TerraFoundationModels` | Apple Foundation Models traced session |
| `TerraMLX` | MLX-swift traced generation |
| `TerraLlama` | llama.cpp C interop bridge |
| `TerraAccelerate` | Accelerate framework attribute builder |
| `TerraTracedMacro` | `@Traced` SwiftSyntax macro |
| `TerraSystemProfiler` | Memory, threads, thermal via Mach APIs |
| `TerraMetalProfiler` | GPU utilization and compute time |
| `TerraTraceKit` | Trace ingestion, OTLP decoding, view models |
| `TraceMacApp` | Native macOS trace viewer |
| `TerraCLI` | CLI trace receiver and renderer |

## Platform Support

| Platform | Minimum |
|---|---|
| macOS | 14.0 |
| iOS | 13.0 |
| tvOS | 13.0 |
| watchOS | 6.0 |
| visionOS | 1.0 |

**Swift** 5.9+ &middot; **OpenTelemetry** compatible &middot; **Apache 2.0**

## Resources

- [Full Feature Reference](docs/TERRA_FEATURES.md) — all 25 features documented in depth
- [Telemetry Schema (terra.v1)](docs/TelemetryConvention/terra-v1.md) — the contract specification
- [Feature Page](docs/terra-features.html) — visual HTML reference

## License

[Apache 2.0](LICENSE)
