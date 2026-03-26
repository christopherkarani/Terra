# Profiler Integration

Terra provides a modular hardware profiling system that lets you capture GPU, CPU, memory, thermal, and ANE metrics alongside your inference telemetry. This article covers setup and usage for each profiler module.

## Overview

Each profiler is a standalone module you can import and use independently:

| Module | Metrics | Platform |
|--------|---------|----------|
| ``TerraSystemProfiler`` | Memory, thermal state | All Apple platforms |
| ``TerraMetalProfiler`` | GPU utilization, memory in flight | All Apple platforms |
| ``TerraPowerProfiler`` | CPU/GPU/ANE power (watts) | macOS only |
| ``TerraANEProfiler`` | ANE execution time, host overhead | All Apple platforms (A12+) |

All profiler results conform to ``TelemetryAttributeConvertible``, making it simple to attach them to any OpenTelemetry span using ``Span/setAttributes(_:)``.

## TerraSystemProfiler

``TerraSystemProfiler`` provides two profiling capabilities: **memory** and **thermal** monitoring.

### Memory Profiling

Capture process memory usage before and after any operation:

```swift
import Terra
import TerraSystemProfiler

TerraSystemProfiler.install()

let startMem = TerraSystemProfiler.captureMemorySnapshot()
// ... run inference ...
let endMem = TerraSystemProfiler.captureMemorySnapshot()

let deltaAttrs = TerraSystemProfiler.memoryDeltaAttributes(start: startMem, end: endMem)
// Produces:
// - process.memory.resident_delta_mb
// - process.memory.peak_mb
```

Attach directly to a span:

```swift
span.setAttributes(deltaAttrs)
```

### Thermal Monitoring

Track device thermal state over a time window:

```swift
let start = ThermalMonitor.sample()
// ... run inference ...
let end = ThermalMonitor.sample()

let profile = ThermalMonitor.profile(start: start, end: end)
span.setAttributes(profile)
```

**Thermal states:** ``ThermalMonitor`` tracks four states (`nominal`, `fair`, `serious`, `critical`). When either sample reaches `serious` or `critical`, the time is counted as throttled in `terra.thermal.time_throttled_s`.

**Attributes emitted:**

- `terra.thermal.state` — Thermal state at end of window
- `terra.thermal.peak_state` — Highest state reached
- `terra.thermal.time_throttled_s` — Seconds spent throttled

## TerraMetalProfiler

``TerraMetalProfiler`` captures GPU metrics during Metal compute workloads.

```swift
import TerraMetalProfiler

TerraMetalProfiler.install()

// During inference...
let attrs = TerraMetalProfiler.attributes(
    gpuUtilization: 0.85,    // 0.0–1.0
    memoryInFlightMB: 256.0,
    computeTimeMS: 12.5
)
span.setAttributes(attrs)
```

**Attributes emitted:**

- `metal.gpu_utilization` — GPU utilization fraction
- `metal.memory_in_flight_mb` — Metal memory in use (MB)
- `metal.compute_time_ms` — Compute kernel time (ms)

## TerraPowerProfiler

> **Platform: macOS only.** Requires `powermetrics` (pre-installed on macOS) and sudo privileges.

``TerraPowerProfiler`` wraps the macOS `powermetrics` tool to sample hardware power consumption:

```swift
import TerraPowerProfiler

// Start collection (requires sudo)
PowerMetricsCollector.start(domains: [.cpu, .gpu, .ane], intervalMs: 500)

// ... run workload ...

let summary = PowerMetricsCollector.stop()
span.setAttributes(summary)
```

**Attributes emitted:**

- `terra.power.cpu_watts` — Average CPU power (W)
- `terra.power.gpu_watts` — Average GPU power (W)
- `terra.power.ane_watts` — Average ANE power (W)
- `terra.power.package_watts` — Average total package power (W)
- `terra.power.sample_count` — Number of samples collected

**Privileges:** `powermetrics` requires root access. Run your process with `sudo` or configure a `launchd` job with elevated privileges.

## TerraANEProfiler

> **Uses private APIs — not App Store compatible.** Requires the `TerraANEProfiler` target.

``ANEHardwareProfiler`` captures Neural Engine execution metrics:

```swift
import TerraANEProfiler

guard ANEHardwareProfiler.isAvailable else { return }

ANEHardwareProfiler.install()

// Use session-based profiling for scoped windows
ANEProfilerSession.start()
// ... run ANE workloads ...
let metrics = ANEProfilerSession.stop()

span.setAttributes(metrics)
```

Or capture one-shot metrics:

```swift
let metrics = ANEHardwareProfiler.captureMetrics()
span.setAttributes(metrics)
```

**Attributes emitted:**

- `terra.ane.hardware_execution_time_ns` — ANE execution time (ns)
- `terra.ane.host_overhead_us` — Host CPU overhead (μs)
- `terra.ane.segment_count` — Number of ANE program segments
- `terra.ane.fully_ane` — Whether entire operation ran on ANE
- `terra.ane.available` — Whether ANE is present on this device

## Unified API: ModelStatsSnapshot

``ModelStatsSnapshot`` aggregates results from multiple profilers into a single telemetry payload:

```swift
import TerraSystemProfiler
import TerraMetalProfiler
import TerraANEProfiler

let snapshot = ModelStatsSnapshot(
    memorySnapshot,    // TerraSystemProfiler.MemorySnapshot
    thermalProfile,    // ThermalProfile
    metalAttrs,        // MetalAttributes (via TelemetryAttributeConvertible)
)
span.setAttributes(snapshot)
```

Any type conforming to ``TelemetryAttributeConvertible`` can be added to a `ModelStatsSnapshot`.

## Configuration via Terra.Configuration

Hardware profiling can be enabled through ``Terra/Configuration``:

```swift
try await Terra.start(.init(preset: .diagnostics))
// Enables:
// - TerraSystemProfiler (memory + thermal via .standard)
// - TerraMetalProfiler (when .metal is set)
// - ANE profiler hooks (when .ane is set)
```

The `Configuration.Profiling` OptionSet lets you request specific profilers:

```swift
var config = Terra.Configuration(preset: .quickstart)
config.profiling = [.memory, .thermal, .metal]
try await Terra.start(config)
```

## Thread Profiling

``ThreadProfiler`` provides a lightweight thread count snapshot:

```swift
let snapshot = ThreadProfiler.capture()
// snapshot.threadCountEstimate — active thread count
// snapshot.sampleTime — wall-clock capture time
```

> Currently uses `ProcessInfo.activeProcessorCount` as an estimate. Mach thread introspection planned for a future release.

## High-Resolution Timing

``MachTime`` provides monotonic high-resolution timestamps for measuring elapsed time:

```swift
let start = MachTime.now()
// ... work ...
let elapsedMs = MachTime.elapsedMilliseconds(from: start, to: MachTime.now())
```

On Darwin, this uses `mach_absolute_time()` which is not affected by system clock changes.
