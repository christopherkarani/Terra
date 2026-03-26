# TerraCore

Core runtime concepts for Terra telemetry.

## Overview

TerraCore provides the foundational types and protocols that power Terra's observability layer. This article covers the privacy model, lifecycle state machine, telemetry engine protocol, and configuration options.

## Agentic and Manual Tracing

Terra exposes three explicit ownership patterns for spans:

- ``Terra/agentic(name:id:_:)`` for multi-step agent loops with child inference and tool work.
- ``Terra/trace(name:id:_:)-swift.method`` for one async task that owns a root span for the duration of the closure.
- ``Terra/startSpan(name:id:attributes:)`` when lifecycle must outlive the current closure and be ended manually.

When a child operation must attach to a specific parent span outside ambient task-local context, bind it with ``Terra/Operation/under(_:)``.

```swift
import Terra

let root = Terra.startSpan(name: "sync")
defer { root.end() }

let value = try await Terra
  .tool("search", callId: "call-1")
  .under(root)
  .run { "ok" }
```

If work crosses a detached-task boundary, use ``Terra/SpanHandle/detached(priority:_:)`` or ``Terra/AgentHandle/detached(priority:_:)`` instead of raw `Task.detached` so the parent span remains linked.

## Privacy Model

Terra's privacy system uses ``Terra/PrivacyPolicy`` to control how sensitive content is handled in traces.

### Privacy Policy Levels

| Policy | Behavior | Use Case |
|--------|----------|----------|
| ``Terra/PrivacyPolicy/redacted`` | HMAC-SHA256 hash of content | Production, default |
| ``Terra/PrivacyPolicy/lengthOnly`` | Only content length captured | Debug without content |
| ``Terra/PrivacyPolicy/capturing`` | Content captured, hashed with HMAC-SHA256 | Development only |
| ``Terra/PrivacyPolicy/silent`` | No content captured | Maximum privacy |

### Redaction Strategies

When content must be redacted, Terra applies one of these strategies:

- ``Terra/RedactionStrategy/drop`` — Content is discarded entirely
- ``Terra/RedactionStrategy/lengthOnly`` — Only the character count is preserved
- ``Terra/RedactionStrategy/hashHMACSHA256`` — HMAC-SHA256 hash using a per-device key stored in Keychain
- ``Terra/RedactionStrategy/hashSHA256`` — Legacy deterministic SHA-256 hash

### Content Capture

By default, Terra does not capture prompt or response content. Opt-in using ``Terra/CapturePolicy``:

```swift
import Terra

// Default: no content capture
let result = try await Terra
  .infer("gpt-4o-mini", prompt: "Hello")
  .run { "response" }

// Include content for this call (privacy policy still applies)
let resultWithContent = try await Terra
  .infer("gpt-4o-mini", prompt: "Hello")
  .capture(.includeContent)
  .run { "response" }
```

### Anonymization Key

Terra generates a per-device anonymization key on first launch and stores it securely in the Keychain. This key is used for HMAC-SHA256 hashing, ensuring that even with the same content, different devices produce different hashes.

## Lifecycle State Machine

``Terra/LifecycleState`` tracks Terra's runtime state and governs valid transitions.

### States

| State | Meaning |
|-------|---------|
| ``Terra/LifecycleState/stopped`` | Terra is not running. ``Terra/start(_:)`` may be called. |
| ``Terra/LifecycleState/starting`` | A start/reconfigure call is in progress. |
| ``Terra/LifecycleState/running`` | Terra is actively collecting and exporting telemetry. |
| ``Terra/LifecycleState/shuttingDown`` | A shutdown/reset/reconfigure call is in progress. |

### Valid Transitions

```
stopped → starting → running → shuttingDown → stopped
              ↑_________|         |
              |                  ↓
              └─── starting ←────┘ (via reconfigure)
```

### Calling Shutdown

``Terra/shutdown()`` is safe to call from any context and is idempotent:

```swift
import Terra

// Start Terra
try await Terra.start()

// ... use Terra ...

// Shutdown when done
await Terra.shutdown()

// Safe to call multiple times — no-op if already stopped
await Terra.shutdown()
```

### Reconfiguring

``Terra/reconfigure(_:)`` performs a shutdown followed by a fresh start atomically:

```swift
import Terra

try await Terra.start(.init(preset: .quickstart))

// Replace with new configuration
try await Terra.reconfigure(.init(preset: .production))

await Terra.shutdown()
```

## TelemetryEngine Protocol

> These seams are `package` scoped and are intended for internal Terra package use, not external SDK consumers.

``Terra/TelemetryEngine`` enables deterministic execution for testing or custom telemetry backends inside the Terra package.

### Package-only Protocol Shape

```swift
package protocol TelemetryEngine: Sendable {
  func run<R: Sendable>(
    context: Terra.TelemetryContext,
    attributes: [Terra.TraceAttribute],
    _ body: @escaping @Sendable (Terra.TraceHandle) async throws -> R
  ) async throws -> R
}
```

### Public SDK Alternative

External SDK consumers should keep using the public operation factories and install a test tracer provider for deterministic verification:

```swift
import Terra
import OpenTelemetrySdk

let tracerProvider = TracerProviderBuilder().build()
Terra.install(.init(
  tracerProvider: tracerProvider,
  registerProvidersAsGlobal: false
))

let result = try await Terra
  .tool("search", callId: "call-1")
  .run { trace in
    trace.event("tool.invoked")
    return "stubbed result"
  }
```

See <doc:TelemetryEngine-Injection> for package-only seam details.

## Configuration

``Terra/Configuration`` provides presets and fine-grained control over Terra's behavior.

### Presets

| Preset | Privacy | Features | Persistence |
|--------|---------|----------|-------------|
| ``Terra/Configuration/Preset/quickstart`` | redacted | coreML, http, sessions, signposts | off |
| ``Terra/Configuration/Preset/production`` | redacted | coreML, http, sessions | balanced |
| ``Terra/Configuration/Preset/diagnostics`` | redacted | coreML, http, sessions, signposts, logs | balanced + profiling |

### Configuration Options

```swift
import Terra

// Using a preset
try await Terra.start(.init(preset: .production))

// Custom configuration
var config = Terra.Configuration(preset: .quickstart)
config.privacy = .capturing  // Override privacy policy
config.profiling = .all      // Enable all profilers
config.features = [.coreML, .http]

try await Terra.start(config)
```

### Features

``Terra/Configuration/Features`` is an OptionSet controlling which instrumentations are enabled:

- ``Terra/Configuration/Features/coreML`` — Auto-instrument CoreML predictions
- ``Terra/Configuration/Features/http`` — Auto-instrument AI API HTTP calls
- ``Terra/Configuration/Features/sessions`` — Enable session tracking
- ``Terra/Configuration/Features/signposts`` — Enable OS signpost integration
- ``Terra/Configuration/Features/logs`` — Enable structured logging

### Profiling

``Terra/Configuration/Profiling`` is an OptionSet for enabling hardware profilers:

- ``Terra/Configuration/Profiling/memory`` — Memory usage tracking
- ``Terra/Configuration/Profiling/thermal`` — Thermal state monitoring
- ``Terra/Configuration/Profiling/metal`` — Metal GPU profiler
- ``Terra/Configuration/Profiling/power`` — Power usage (requires separate target)
- ``Terra/Configuration/Profiling/espresso`` — macOS power metrics
- ``Terra/Configuration/Profiling/ane`` — Apple Neural Engine profiler (requires separate target)

Predefined tiers:
- ``Terra/Configuration/Profiling/standard`` — memory + thermal
- ``Terra/Configuration/Profiling/extended`` — standard + metal + power
- ``Terra/Configuration/Profiling/all`` — All profilers including espresso and ane

## See Also

- <doc:Canonical-API> — Complete API reference
- <doc:TelemetryEngine-Injection> — Advanced engine injection patterns
- <doc:Metadata-Builder> — Attaching span metadata
- <doc:Quickstart-90s> — Getting started guide
