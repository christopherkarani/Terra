# Configuration Reference

Complete reference for ``Terra/Configuration`` and all associated types.

## Terra.Configuration

```swift
public struct Configuration: Sendable, Equatable
```

The main configuration type for Terra startup.

### Presets

```swift
public enum Preset: Sendable, Equatable {
    case quickstart
    case production
    case diagnostics
}
```

| Preset | Privacy | Features | Persistence | Profiling |
|--------|---------|----------|-------------|-----------|
| `quickstart` | `.redacted` | CoreML, HTTP, Sessions, Signposts | Off | None |
| `production` | `.redacted` | CoreML, HTTP, Sessions | Balanced | None |
| `diagnostics` | `.redacted` | CoreML, HTTP, Sessions, Signposts, Logs | Balanced | Standard |

### Initialization

```swift
public init(preset: Preset = .quickstart)
```

Creates a configuration from a preset.

```swift
// Quickstart (default)
let quickstart = Terra.Configuration()

// Production
let production = Terra.Configuration(preset: .production)

// Diagnostics
let diagnostics = Terra.Configuration(preset: .diagnostics)
```

### Properties

#### privacy

```swift
public var privacy: Terra.PrivacyPolicy
```

Content privacy policy controlling how prompts and responses are handled.

| Value | Behavior |
|-------|----------|
| `.redacted` | Hash with HMAC-SHA256, emit length + hash |
| `.lengthOnly` | Emit only character/byte count |
| `.capturing` | Capture content but hash for privacy |
| `.silent` | Drop all content |

**Default**: `.redacted`

```swift
var config = Terra.Configuration()
config.privacy = .redacted
```

#### destination

```swift
public var destination: Destination
```

Where telemetry is exported.

```swift
public enum Destination: Sendable, Equatable {
    case localDashboard       // http://127.0.0.1:4318
    case endpoint(URL)        // Custom OTLP endpoint
}
```

**Default**: `.localDashboard`

```swift
// Local dashboard
config.destination = .localDashboard

// Custom endpoint
config.destination = .endpoint(URL(string: "https://otlp.company.com:4318")!)
```

#### features

```swift
public var features: Features
```

Which auto-instrumentations to enable.

```swift
public struct Features: OptionSet, Sendable, Equatable {
    public static let coreML    = Features(rawValue: 1 << 0)  // CoreML auto-instrumentation
    public static let http      = Features(rawValue: 1 << 1)  // HTTP AI API instrumentation
    public static let sessions  = Features(rawValue: 1 << 2)  // Session tracing
    public static let signposts = Features(rawValue: 1 << 3)  // Signpost instrumentation
    public static let logs      = Features(rawValue: 1 << 4)  // Log instrumentation
}
```

**Default** (quickstart): `[.coreML, .http, .sessions, .signposts]`

```swift
// Enable CoreML only
config.features = [.coreML]

// Enable CoreML and HTTP
config.features = [.coreML, .http]

// All features
config.features = [.coreML, .http, .sessions, .signposts, .logs]
```

#### persistence

```swift
public var persistence: Persistence
```

How to persist telemetry data before export.

```swift
public enum Persistence: Sendable, Equatable {
    case off                              // No persistence, export immediately
    case balanced(URL)                    // Balanced performance/ durability
    case instant(URL)                      // Higher durability, more disk I/O
}
```

**Default**: `.off` (quickstart), `.balanced(...)` using a cache-backed Terra storage URL (production/diagnostics)

```swift
// Disable persistence
config.persistence = .off

// Balanced persistence
let storageURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Terra")
config.persistence = .balanced(storageURL)

// Instant persistence (higher durability)
config.persistence = .instant(storageURL)
```

**Persistence Performance Tiers**:

| Tier | Write Mode | Export Delay | Use Case |
|------|------------|--------------|----------|
| `.balanced` | Async | 5s default | Production |
| `.instant` | Sync | 3s default | High-value data |

#### profiling

```swift
public var profiling: Profiling
```

Hardware profiling features to enable.

```swift
public struct Profiling: OptionSet, Sendable, Hashable {
    public static let memory   = Profiling(rawValue: 1 << 0)   // Memory profiling
    public static let metal   = Profiling(rawValue: 1 << 1)   // Metal GPU profiling
    public static let thermal = Profiling(rawValue: 1 << 2)   // Thermal state monitoring
    public static let power   = Profiling(rawValue: 1 << 3)   // Power metrics (macOS)
    public static let espresso = Profiling(rawValue: 1 << 4)  // CPU frequency/performance state (macOS)
    public static let ane     = Profiling(rawValue: 1 << 5)   // ANE hardware profiling

    // Tier presets
    public static let standard: Profiling = [.memory, .thermal]
    public static let extended: Profiling = [.memory, .thermal, .metal, .power]
    public static let all: Profiling      = [.memory, .thermal, .metal, .power, .espresso, .ane]
}
```

**Default**: `[]` (none)

```swift
// Standard profiling (memory + thermal)
config.profiling = .standard

// Extended profiling (adds Metal)
config.profiling = .extended

// All profilers
config.profiling = .all

// Specific profilers
config.profiling = [.memory, .thermal, .metal]
```

---

## Complete Configuration Examples

### Minimal Quickstart

```swift
import Terra

try await Terra.start()
```

Equivalent to:

```swift
import Terra

try await Terra.start(.init())
```

### Production with Persistence

```swift
import Terra

var config = Terra.Configuration(preset: .production)
config.persistence = .balanced(
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Terra", isDirectory: true)
)
try await Terra.start(config)
```

### Diagnostics with Custom Endpoint

```swift
import Terra

var config = Terra.Configuration(preset: .diagnostics)
config.destination = .endpoint(URL(string: "https://otlp.company.com:4318")!)
config.persistence = .balanced(
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TerraDiagnostics")
)
try await Terra.start(config)
```

### High-Privacy Configuration

```swift
import Terra

var config = Terra.Configuration()
config.privacy = .lengthOnly  // Only record lengths, no hashes
config.features = [.coreML]    // Minimal instrumentation
config.persistence = .off     // No local persistence
try await Terra.start(config)
```

### Custom Feature Set

```swift
import Terra

var config = Terra.Configuration()
config.features = [.coreML, .http]  // Only CoreML and HTTP, no sessions
config.privacy = .redacted
try await Terra.start(config)
```

### ANE Hardware Profiling

```swift
import Terra

var config = Terra.Configuration(preset: .diagnostics)
config.profiling = [.memory, .thermal, .ane]
config.features = [.coreML]
try await Terra.start(config)
```

---

## Terra.PrivacyPolicy

```swift
public enum PrivacyPolicy: String, Sendable, Hashable
```

Controls how sensitive content is handled.

| Case | Content | Hash | Length | Use Case |
|------|---------|------|--------|----------|
| `.redacted` | Dropped | HMAC-SHA256 | Yes | Production default |
| `.lengthOnly` | Dropped | None | Yes | Maximum privacy |
| `.capturing` | Hashed | HMAC-SHA256 | Yes | Debug builds |
| `.silent` | Dropped | None | No | Testing |

### Content Redaction Behavior

```swift
config.privacy = .redacted
// Prompt "Hello world" (11 chars) emits:
//   terra.prompt.length = 11
//   terra.prompt.hmac_sha256 = "a4a3f7..."
//   terra.anonymization_key_id = "key-abc123"
```

---

## Endpoint Configuration

### Local Dashboard

```swift
config.destination = .localDashboard
// Exports to http://127.0.0.1:4318
```

### Custom OTLP Endpoint

```swift
config.destination = .endpoint(
    URL(string: "https://otlp.example.com:4318")!
)
```

**Requirements**:

- Must use `http` or `https` scheme
- Must include a host
- Port 4318 is standard for OTLP HTTP

**Endpoint Path Resolution**:

| Component | Path |
|-----------|------|
| Traces | `/v1/traces` |
| Metrics | `/v1/metrics` |
| Logs | `/v1/logs` |

---

## Persistence Storage

### Storage URL Requirements

- Must be a directory (not a file)
- Application must have write permissions
- Sufficient disk space for telemetry buffer

### Default Storage Location

```swift
FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
  .appendingPathComponent("Terra", isDirectory: true)
```

### Manual Storage Setup

```swift
import Terra

let storageURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("MyApp", "TerraTelemetry", isDirectory: true)

// Create directory if needed
try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)

var config = Terra.Configuration(preset: .production)
config.persistence = .balanced(storageURL)
```

---

## Profiling Options

### Memory Profiling

```swift
config.profiling = .standard  // Includes memory
// or
config.profiling = [.memory]
```

Captures:

- `process.memory.resident_delta_mb`
- `process.memory.peak_mb`

### Thermal Monitoring

```swift
config.profiling = .standard  // Includes thermal
// or
config.profiling = [.thermal]
```

Captures:

- `terra.thermal.state`
- `terra.thermal.peak_state`
- `terra.thermal.time_throttled_s`

### Metal Profiling

```swift
config.profiling = .extended  // Includes Metal
// or
config.profiling = [.metal]
```

Requires `TerraMetalProfiler` integration.

### Power Profiling (macOS)

```swift
config.profiling = .extended  // Includes power
// or
config.profiling = [.power]
```

Requires `TerraPowerProfiler` integration.

### Espresso Capture (macOS)

```swift
config.profiling = .all  // Includes espresso
// or
config.profiling = [.espresso]
```

Captures GPU compute metrics via Espresso framework.

### ANE Hardware Profiling

```swift
config.profiling = [.memory, .thermal, .ane]
```

Requires `TerraANEProfiler` integration (non-App-Store).

Captures:

- `terra.ane.hardware_execution_time_ns`
- `terra.ane.host_overhead_us`
- `terra.ane.segment_count`
- `terra.ane.fully_ane`
- `terra.ane.available`

---

## Feature Flags

### CoreML

```swift
config.features = [.coreML]
```

Enables automatic tracing of `MLModel.prediction(from:)` calls.

### HTTP AI APIs

```swift
config.features = [.http]
```

Enables automatic tracing of HTTP requests to known AI API endpoints (OpenAI, Anthropic, etc.).

### Sessions

```swift
config.features = [.sessions]
```

Enables session-level span correlation.

### Signposts

```swift
config.features = [.signposts]
```

Enables OS signpost integration for performance analysis in Instruments.

### Logs

```swift
config.features = [.logs]
```

Enables structured log export alongside traces and metrics.

---

## Configuration Validation

Terra validates configuration at ``Terra/start(_:)`` time:

| Error Code | Cause | Remediation |
|------------|-------|-------------|
| `.invalid_endpoint` | Invalid URL scheme or missing host | Use http/https with host |
| `.persistence_setup_failed` | Storage directory not writable | Check permissions |
| `.already_started` | Terra already running | Call shutdown first |
| `.invalid_lifecycle_state` | Invalid state transition | Check lifecycle |

### Error Handling Example

```swift
import Terra

do {
    try await Terra.start(config)
} catch let error as Terra.TerraError {
    switch error.code {
    case .invalid_endpoint:
        print("Fix endpoint URL: \(error.context)")
    case .persistence_setup_failed:
        print("Storage error: \(error.context)")
    case .already_started:
        await Terra.shutdown()
        try await Terra.start(config)
    default:
        print("Error: \(error.message)")
    }
}
```

---

## See Also

- <doc:Canonical-API> - Complete API map
- <doc:API-Reference> - API reference
- <doc:TerraError-Model> - Error handling
- <doc:TerraCore> - Privacy and lifecycle configuration
