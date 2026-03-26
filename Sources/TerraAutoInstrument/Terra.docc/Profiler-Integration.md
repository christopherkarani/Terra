# Hardware Profiling

Terra provides hardware-level profiling for Apple platforms to help optimize GenAI workload performance.

## Overview

| Profiler | Purpose | Platform |
|----------|---------|----------|
| ``TerraANEProfiler`` | Apple Neural Engine metrics | iOS 17+, macOS 14+ |
| ``TerraMetalProfiler`` | Metal GPU utilization | All Apple platforms |
| ``TerraSystemProfiler`` | Memory and thermal state | All Apple platforms |
| ``TerraPowerProfiler`` | Battery and energy impact | macOS only |

## Topics

### TerraANEProfiler

Apple Neural Engine profiling via private APIs. Captures hardware utilization, memory pressure, and compute time for ANE operations.

> **Non-App-Store Notice:** ANE profiling uses private APIs and is excluded from App Store builds. Enable only for development/testing builds.

#### Availability Check

```swift
import TerraANEProfiler

if ANEHardwareProfiler.isAvailable {
  // ANE is available on this device
}
```

#### Session-Based Profiling

```swift
ANEProfilerSession.start()

// Your ANE inference code
let result = try await mlModel.prediction(features: input)

// Capture metrics
let metrics = ANEProfilerSession.stop()
// metrics: ANEHardwareMetrics
```

#### ANEHardwareMetrics

| Field | Type | Description |
|-------|------|-------------|
| `hardwareExecutionTimeNs` | `UInt64` | ANE hardware execution time in nanoseconds |
| `hostOverheadUs` | `Double` | Host CPU overhead in microseconds |
| `segmentCount` | `Int32` | Number of ANE program segments |
| `fullyANE` | `Bool` | Whether entire operation ran on ANE |
| `available` | `Bool` | Whether ANE is available |

### TerraMetalProfiler

Metal GPU profiling for compute and graphics workloads.

#### Installation

```swift
import TerraMetalProfiler

TerraMetalProfiler.install()
```

#### GPU Metrics

```swift
let attributes = TerraMetalProfiler.attributes(
  gpuUtilization: 0.85,
  memoryInFlightMB: 512.0,
  computeTimeMS: 12.5
)
```

#### GPU Metric Attributes

| Metric | Key | Description |
|--------|-----|-------------|
| `gpuUtilization` | `metal.gpu_utilization` | GPU utilization as fraction (0-1) |
| `memoryInFlightMB` | `metal.memory_in_flight_mb` | Memory in use by GPU in MB |
| `computeTimeMS` | `metal.compute_time_ms` | GPU compute time in milliseconds |

### TerraSystemProfiler

System-level profiling including memory snapshots and thermal monitoring.

#### Memory Snapshots

```swift
import TerraSystemProfiler

let snapshot = TerraSystemProfiler.captureMemorySnapshot()
// snapshot: TerraSystemProfiler.MemorySnapshot

// Compare deltas
let start = TerraSystemProfiler.captureMemorySnapshot()
await performInference()
let end = TerraSystemProfiler.captureMemorySnapshot()

let delta = TerraSystemProfiler.memoryDeltaAttributes(start: start, end: end)
// Returns attributes for memory growth during inference
```

#### Memory Snapshot Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `process.memory.resident_bytes` | int | Resident memory in bytes |
| `process.memory.resident_mb` | double | Resident memory in megabytes |
| `process.memory.resident_delta_mb` | double | Change in resident memory |
| `process.memory.peak_mb` | double | Highest memory seen |

#### Thermal Monitoring

```swift
let thermal = ThermalMonitor.sample()
// thermal: ThermalSample with state (ProcessInfo.ThermalState)

if thermal.state == .critical {
  // Reduce workload or skip heavy inference
}
```

### TerraPowerProfiler

Power and energy consumption profiling using `powermetrics` (macOS only).

#### Power Domains

```swift
import TerraPowerProfiler

let domains: PowerDomains = [.cpu, .gpu, .ane]
// Or: .cpu, .gpu, .ane individually

PowerMetricsCollector.start(domains: domains, intervalMs: 100)

// ... perform work ...

let summary = PowerMetricsCollector.stop()
// summary: PowerSummary with energy consumption estimates
```

#### Power Summary Attributes

| Attribute | Key | Description |
|-----------|-----|-------------|
| `averageCpuWatts` | `terra.power.cpu_watts` | Average CPU power in watts |
| `averageGpuWatts` | `terra.power.gpu_watts` | Average GPU power in watts |
| `averageAneWatts` | `terra.power.ane_watts` | Average ANE power in watts |
| `averagePackageWatts` | `terra.power.package_watts` | Average total package power |
| `sampleCount` | `terra.power.sample_count` | Number of samples aggregated |

## Complete Example

```swift
import Terra

// Configure profiling in Terra
var config = Terra.Configuration(preset: .diagnostics)
config.profiling = [.memory, .thermal, .metal]
try await Terra.start(config)

// Or use ANE profiling separately (non-App-Store)
if ANEHardwareProfiler.isAvailable {
  ANEProfilerSession.start()

  // Your Core ML inference
  let result = try await model.prediction(features: input)

  let metrics = ANEProfilerSession.stop()
  print("ANE HW Time: \(metrics.hardwareExecutionTimeNs)ns")
}

// Memory delta for inference
let startMem = TerraSystemProfiler.captureMemorySnapshot()
let _ = try await inference()
let endMem = TerraSystemProfiler.captureMemorySnapshot()

let delta = TerraSystemProfiler.memoryDeltaAttributes(start: startMem, end: endMem)
// Attach to a workflow or child span: span.attribute("memory.delta_bytes", delta["memory.delta_bytes"] ?? .int(0))
```

## Configuration

Enable profilers via ``Terra/Configuration/Profiling``:

```swift
var config = Terra.Configuration()

// Standard profilers (App Store safe)
config.profiling = [.memory, .thermal, .metal]

// Extended profilers (development only)
config.profiling = [.memory, .thermal, .power, .metal, .ane, .espresso]

// All profilers
config.profiling = .all
```

### Profiling Presets

```swift
public struct Profiling: OptionSet {
    // Individual options
    public static let memory   // TerraSystemProfiler
    public static let metal    // TerraMetalProfiler
    public static let thermal  // ThermalMonitor
    public static let power    // PowerMetricsCollector
    public static let espresso  // EspressoLogCapture (macOS)
    public static let ane      // ANEHardwareProfiler

    // Presets
    public static let standard: Profiling = [.memory, .thermal]
    public static let extended: Profiling = [.memory, .thermal, .metal, .power]
    public static let all: Profiling      = [.memory, .thermal, .metal, .power, .espresso, .ane]
}
```

> **Warning:** `.ane` and `.espresso` use private APIs and are excluded from App Store submissions.

## See Also

- <doc:Canonical-API>
- <doc:Configuration-Reference>
- <doc:Metadata-Builder>
