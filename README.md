<p align="center">
  <img src="terra-banner.svg" alt="Terra" width="100%" />
</p>

<p align="center">
  <strong>Terra adds tracing to GenAI apps. The Swift package is the part most people will use. The rest of the repo holds the other bindings and the native-core code.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" alt="License" /></a>
  <img src="https://img.shields.io/badge/Swift-5.9+-orange.svg" alt="Swift 5.9+" />
  <img src="https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20visionOS-red.svg" alt="Platforms" />
</p>

---

Terra instruments model inference, streaming, agents, tool calls, embeddings, safety checks, Core ML calls, and HTTP AI requests. By default it keeps content capture off and export local.

```swift
import Terra

try await Terra.start()
```

## Swift package products

| Product | Purpose |
|---------|---------|
| `Terra` | Umbrella target with auto-instrumentation and lifecycle setup |
| `TerraCore` | Core API, privacy, lifecycle, and trace types |
| `TerraCoreML` | Core ML instrumentation helpers |
| `TerraTraceKit` | OpenTelemetry helpers and renderers |
| `TerraHTTPInstrument` | HTTP AI request instrumentation |
| `TerraFoundationModels` | Apple Foundation Models integration |
| `TerraMLX` | MLX integration helpers |
| `TerraMetalProfiler` | Metal profiling hooks |
| `TerraSystemProfiler` | Memory profiling hooks |
| `TerraAccelerate` | Accelerate backend attributes |
| `TerraTracedMacro` | `@Traced` macro support |

### Install

```swift
dependencies: [
    .package(url: "https://github.com/christopherkarani/Terra.git", from: "0.1.0")
]
```

Swift consumers use the vendored `libtera.xcframework`. If you're working on the native core, start in `zig-core/`.

## Quick Start

```swift
import Terra

try await Terra.start(.init(preset: .production))

let answer = try await Terra
    .infer(Terra.ModelID("gpt-4o-mini"), prompt: prompt)
    .execute { trace in
        trace.tokens(input: 128, output: 64)
        return try await llm.generate(prompt)
    }
```

For function-level instrumentation, use `@Traced` from `TerraTracedMacro`.

## Other Repo Parts

The repo also contains bindings and tooling that share the native core:

- `terra-python/`
- `terra-rust/`
- `terra-cpp/`
- `terra-android/`
- `terra-ros2/`
- `zig-core/`

These directories are useful if you're working on the bindings or the native core. Most users will only need the Swift package.

## More Docs

- [Cookbook](Docs/cookbook.md) - copy-paste recipes and advanced patterns
- [Migration](Docs/migration.md) - upgrade notes for older integrations
- [Integrations](Docs/integrations.md) - Core ML and MLX integration guidance
- [DocC reference](Sources/TerraAutoInstrument/Terra.docc/Terra.md) - package reference and guided docs

## Repository Layout

- `Sources/` - Swift package targets
- `Tests/` - unit and integration tests
- `Examples/` - runnable samples
- `Benchmarks/` - benchmark executable targets
- `Docs/` - hand-written public guides
- `terra-python/`, `terra-rust/`, `terra-cpp/`, `terra-android/`, `terra-ros2/` - companion bindings and integration surfaces
- `zig-core/` - native core and C ABI bridge
- `Vendor/` - vendored binary artifacts for Swift consumers

## Requirements

| Platform | Minimum |
|----------|---------|
| iOS | 13.0+ |
| macOS | 14.0+ |
| visionOS | 1.0+ |
| tvOS | 13.0+ |
| watchOS | 6.0+ |
| Swift / Xcode | 5.9+ / Xcode 15+ |
| Zig | 0.14+ for native-core work |
| Python | 3.8+ |
| Rust | 2021 edition |
| C++ | C++17 |
| Android | minSdk 26 |

## Notes

- Content capture is opt-in. The default configuration redacts sensitive fields.
- The repo-local bindings stay in-tree so the native core, wrappers, and tests stay in sync.
- `TerraSample` and `TerraSDKBenchmarks` are executable targets for examples and performance checks.

## License

Released under the [Apache 2.0 License](LICENSE).
