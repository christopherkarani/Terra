# Terra Model Stats Enhancement Plan

**Version:** 1.0  
**Date:** March 20, 2026  
**Status:** Draft for Review

---

## Executive Summary

This document outlines a phased implementation plan for enhancing Terra with comprehensive model performance statistics. Based on research into three reference codebases (espresso, anemll-bench, and Terra itself), we identify measurable metrics that can be collected using public APIs, platform-specific tools, and derived calculations.

### Key Finding
No public API provides real-time ANE/GPU utilization percentages on Apple platforms. All available approaches use either:
- **Derived metrics** (calculated from observable values)
- **Timing heuristics** (inferring device from performance characteristics)
- **Private APIs** (with App Store distribution risks)
- **External tools** (requiring elevated privileges)

---

## Research Sources & Methodology

### Primary Sources Analyzed

| Source | Location | Key Contributions |
|--------|----------|-------------------|
| **Terra** | `~/CodingProjects/Terra/` | Base architecture, OpenTelemetry tracing, memory profiling |
| **espresso** | `~/CodingProjects/espresso/` | ANE interop, power telemetry via powermetrics, thermal monitoring |
| **anemll-bench** | `https://github.com/Anemll/anemll-bench` | Bandwidth calculation methodology, timing heuristics |

### Apple Documentation References

1. **ProcessInfo.thermalState**
   - Source: [Apple Developer Documentation](https://developer.apple.com/documentation/foundation/processinfo/thermalstate)
   - Availability: iOS 11.0+, macOS 10.10+, watchOS 4.0+, tvOS 11.0+
   - API Status: **Public**

2. **mach_absolute_time()**
   - Source: [Apple Developer Documentation](https://developer.apple.com/library/archive/qa/qa1398/_index.html)
   - Purpose: High-precision timing for kernel profiling
   - API Status: **Public** (Darwin kernel)

3. **powermetrics**
   - Source: [macOS man pages](https://www.unix.com/man-page/macosx/8/powermetrics/)
   - Purpose: CPU/GPU/ANE power and performance monitoring
   - Requirements: **Root/sudo access required**
   - Platform: **macOS only**

4. **CoreML Compute Units**
   - Source: [CoreML Documentation](https://developer.apple.com/documentation/coreml/mlcomputeunits)
   - Options: `.cpuOnly`, `.cpuAndGPU`, `.cpuAndNeuralEngine`, `.all`
   - Limitation: **Must be set at load time; cannot query runtime device selection**

---

## Current State Analysis

### Terra's Existing Capabilities

Based on source analysis of `/Users/chriskarani/CodingProjects/Terra/`:

| Component | File | Current Capability |
|-----------|------|-------------------|
| **Memory Profiler** | `TerraSystemProfiler.swift` | Resident memory via `mach_task_basic_info` [1] |
| **Metal Profiler** | `TerraMetalProfiler.swift` | Manual GPU utilization input (no automatic collection) |
| **ANE Profiler** | `NeuralEngineResearch.swift` | Placeholder only - no implementation |
| **CoreML Diagnostics** | `MLComputePlanDiagnostics.swift` | Per-operation device preferences (compute plan analysis) |
| **Tracing** | `Terra.swift`, `TerraTracer.swift` | OpenTelemetry-based spans for inference, tokens, KV cache |

### Gaps Identified

1. **No thermal monitoring** - Critical for sustained inference performance
2. **No power metrics** - Cannot measure energy consumption
3. **No bandwidth calculations** - Missing derived throughput metrics
4. **No compute device inference** - Cannot determine actual runtime execution target
5. **Limited ANE visibility** - No hardware execution time or utilization data

---

## Implementation Plan

### Phase 1: Public API Metrics (Foundation)
**Priority:** High  
**Effort:** 2-3 days  
**Risk:** None (all public APIs)  
**Platform Support:** iOS, macOS, watchOS, tvOS

#### 1.1 Thermal Monitoring Module

**Source Basis:**
- espresso: `Sources/EspressoBench/ThermalMonitor.swift` [2]
- Apple: `ProcessInfo.thermalState` documentation [3]

**Implementation:**
```swift
// Sources/TerraSystemProfiler/ThermalMonitor.swift
import Foundation

public final class ThermalMonitor: @unchecked Sendable {
    public private(set) var currentState: ProcessInfo.ThermalState
    public func startMonitoring(interval: TimeInterval = 1.0)
    public func stopMonitoring() -> ThermalProfile
}

public struct ThermalProfile: Sendable {
    public let samples: [(timestamp: Date, state: ProcessInfo.ThermalState)]
    public let peakState: ProcessInfo.ThermalState
    public let timeInSeriousCritical: TimeInterval
}
```

**States:**
- `.nominal` - Normal operating temperature
- `.fair` - Slightly elevated, moderate performance impact
- `.serious` - Significant performance throttling likely
- `.critical` - Severe throttling, potential thermal shutdown

#### 1.2 Model Size Detection

**Source Basis:**
- anemll-bench: `anemll_bench/benchmark.py:_get_model_size_bytes()` [4]

**Implementation:**
```swift
// Sources/TerraCoreML/ModelSizeDetector.swift
public enum ModelSizeDetector {
    public static func detectSize(of modelURL: URL) -> UInt64?
    
    // Scans:
    // - .mlmodelc/weights/*.bin (compiled model weights)
    // - .mlpackage/Data/com.apple.CoreML/weights/* (package weights)
}
```

**Reference Implementation:**
```python
# From anemll-bench benchmark.py (lines 243-280)
if model_path.endswith('.mlmodelc'):
    weights_dir = os.path.join(model_path, 'weights')
    # Sum all .bin files
elif model_path.endswith('.mlpackage'):
    weights_dir = os.path.join(model_path, 'Data', 'com.apple.CoreML', 'weights')
    # Sum all files in weights directory
```

#### 1.3 Calculated Bandwidth

**Source Basis:**
- anemll-bench: `anemll_bench/benchmark.py:_calculate_throughput()` [4]
- Formula: `throughput_gb_s = model_size_gb / inference_time_s`

**Implementation:**
```swift
// Sources/TerraCoreML/CalculatedMetrics.swift
public struct CalculatedMetrics: Sendable {
    public let modelSizeBytes: UInt64
    public let inferenceTimeMs: Double
    
    public var bandwidthGBs: Double {
        let modelSizeGB = Double(modelSizeBytes) / 1e9
        let inferenceTimeS = inferenceTimeMs / 1000.0
        return modelSizeGB / inferenceTimeS
    }
}
```

**Rationale:**
As noted in anemll-bench documentation: "This metric measures how efficiently your model uses the available memory bandwidth. It is calculated by: Throughput (GB/s) = Model Size (GB) / Inference Time (seconds)" [5]

#### 1.4 Compute Device Heuristics

**Source Basis:**
- anemll-bench: Timing-based classification in `benchmark.py` [4]
- espresso: `InferenceKernelProfile.swift` hardware timing separation [2]

**Heuristic Thresholds (from anemll-bench):**
```
< 5ms   -> Very fast (likely ANE)
< 20ms  -> Fast (possibly ANE)
20-100ms -> Moderate (CPU/GPU mixed)
> 100ms -> Slow (likely CPU only)
```

**Implementation:**
```swift
public enum ComputeDeviceGuess: String, Sendable {
    case likelyANE = "likely_ane"      // < 20ms
    case likelyGPU = "likely_gpu"      // 20-100ms
    case likelyCPU = "likely_cpu"      // > 100ms
    case unknown = "unknown"
    
    init(inferenceTimeMs: Double) {
        switch inferenceTimeMs {
        case ..<20: self = .likelyANE
        case 20..<100: self = .likelyGPU
        default: self = .likelyCPU
        }
    }
}
```

---

### Phase 2: macOS Power Metrics (Platform-Specific)
**Priority:** Medium  
**Effort:** 3-5 days  
**Risk:** Low (requires sudo, but uses official tool)  
**Platform Support:** macOS only

#### 2.1 PowerMetrics Collector

**Source Basis:**
- espresso: `Sources/EspressoGenerate/PowerTelemetry.swift` [2]
- Apple: powermetrics man page [6]

**Implementation:**
```swift
#if os(macOS)
// Sources/TerraSystemProfiler/PowerMetricsCollector.swift
import Foundation

public final class PowerMetricsCollector: @unchecked Sendable {
    public func start(samplers: [PowerSampler] = [.cpu, .gpu, .ane])
    public func stop() -> PowerSummary
}

public struct PowerSummary: Sendable {
    public let averagePackagePowerW: Double
    public let averageCPUPowerW: Double
    public let averageGPUPowerW: Double
    public let averageANEPowerW: Double
    public let sampleCount: Int
}

public enum PowerSampler: String {
    case cpu = "cpu_power"
    case gpu = "gpu_power"
    case ane = "ane_power"
}
#endif
```

**Technical Details:**
- Spawns `/usr/bin/powermetrics` via `Process`
- Requires passwordless sudo or root privileges
- Sampling interval: 100-1000ms (configurable)
- Parses output using regex pattern: `(?im)^\s*(CPU Power|GPU Power|ANE Power|Package Power)\s*:\s*([0-9]+(?:\.[0-9]+)?)\s*(mW|W)\s*$`

**Reference Implementation (from espresso):**
```swift
// From PowerTelemetry.swift (lines 64-105)
process.arguments = [
    "-n", "sudo",
    "/usr/bin/powermetrics",
    "--samplers", "cpu_power,gpu_power,ane_power",
    "--sample-interval", String(sampleIntervalMs),
]
```

**Limitations:**
- Not available on iOS (no powermetrics binary)
- Requires user to configure sudoers or run as root
- ~1 second sampling latency

---

### Phase 3: Advanced ANE Profiling (Private APIs)
**Priority:** Low  
**Effort:** 5-7 days  
**Risk:** High (private framework usage)  
**Platform Support:** iOS, macOS (with caveats)

#### 3.1 ANE Hardware Execution Time

**Source Basis:**
- espresso: `Sources/ANEInterop/ane_interop.m` [2]
- Private framework: `AppleNeuralEngine.framework`

**Implementation:**
```swift
// Sources/TerraANEProfiler/ANEHardwareProfiler.swift
#if canImport(AppleNeuralEngine)
import AppleNeuralEngine

public struct ANEHardwareMetrics: Sendable {
    public let hardwareExecutionTimeNs: UInt64
    public let hostOverheadUs: Double
    public let totalEvalTimeUs: Double
}
#endif
```

**Technical Details (from espresso):**
```objc
// From ane_interop.m (lines 402-420)
Class perfClass = NSClassFromString(@"_ANEPerformanceStats");
SEL makeSel = @selector(statsWithRequestPerformanceBuffer:statsBufferSize:);
if (perfClass && [perfClass respondsToSelector:makeSel]) {
    void *buf = NULL;
    unsigned int bufSize = 0;
    perfStats = ((id(*)(Class,SEL,void **, unsigned int *))objc_msgSend)(
        perfClass, makeSel, &buf, &bufSize);
}
```

**Risk Assessment:**
| Risk | Severity | Mitigation |
|------|----------|------------|
| App Store rejection | High | Gate behind compile-time flag; document for enterprise/internal use only |
| API breakage | Medium | Runtime class/method probing; graceful degradation |
| Device compatibility | Low | Only load on Apple Silicon; fallback to heuristics |

---

## Technical Specifications

### Data Model Enhancements

```swift
// Sources/Terra/ModelStats.swift
public struct ModelStatsSnapshot: Sendable {
    // Phase 1: Public APIs
    public let timestamp: Date
    public let thermalState: ThermalSnapshot
    public let calculatedMetrics: CalculatedMetrics
    public let computeDeviceGuess: ComputeDeviceGuess
    public let memorySnapshot: MemorySnapshot  // Existing
    
    // Phase 2: macOS Power
    #if os(macOS)
    public let powerMetrics: PowerMetrics?
    #endif
    
    // Phase 3: ANE Hardware
    public let aneHardwareMetrics: ANEHardwareMetrics?
}

public struct ThermalSnapshot: Sendable {
    public let currentState: ProcessInfo.ThermalState
    public let sampleDuration: TimeInterval
    public let peakState: ProcessInfo.ThermalState
}

public struct CalculatedMetrics: Sendable {
    public let modelSizeBytes: UInt64
    public let inferenceTimeMs: Double
    public let bandwidthGBs: Double  // Derived
    public let throughputTokensPerSecond: Double?  // If token count available
}
```

### OpenTelemetry Integration

New semantic conventions for model inference:

| Attribute | Type | Description | Source |
|-----------|------|-------------|--------|
| `model.size.bytes` | Int | Model weight file size | Calculated |
| `model.bandwidth.gbps` | Double | Calculated bandwidth GB/s | Derived |
| `model.compute_device.guess` | String | likely_ane/likely_gpu/likely_cpu | Heuristic |
| `thermal.state` | String | nominal/fair/serious/critical | ProcessInfo |
| `thermal.peak_state` | String | Highest state during inference | ProcessInfo |
| `power.cpu.watts` | Double | Average CPU power | powermetrics |
| `power.gpu.watts` | Double | Average GPU power | powermetrics |
| `power.ane.watts` | Double | Average ANE power | powermetrics |
| `power.package.watts` | Double | Total SoC power | powermetrics |
| `ane.hardware_time.ns` | Int | Hardware execution time | _ANEPerformanceStats |
| `ane.host_overhead.us` | Double | Host overhead | _ANEPerformanceStats |

---

## Risk Assessment

| Phase | Risk | Likelihood | Impact | Mitigation |
|-------|------|------------|--------|------------|
| 1 | API availability on older OS | Medium | Low | @available checks; graceful fallback |
| 1 | Thermal state sampling overhead | Low | Low | 1-second intervals; minimal CPU impact |
| 2 | powermetrics not available | Medium | Medium | Feature detection; skip power metrics |
| 2 | sudo requirements | High | Low | Document setup; optional feature |
| 3 | App Store rejection | High | High | Conditional compilation; enterprise only |
| 3 | Private API changes | Medium | Medium | Runtime probing; version detection |

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Thermal coverage** | 100% of inference calls | All traces include thermal state |
| **Bandwidth accuracy** | Within 10% of theoretical max | Compare to chip specifications |
| **Device guess accuracy** | 85% correct classification | Manual verification on known models |
| **Power metric availability** | 90% on macOS with setup | Success rate of powermetrics spawning |
| **ANE hardware time** | 95% availability (Phase 3) | Success rate of private API calls |
| **Performance overhead** | < 5% inference time increase | Benchmark with/without stats collection |

---

## Implementation Timeline

| Week | Deliverable | Owner |
|------|-------------|-------|
| 1 | Phase 1: Thermal monitoring, model size detection | TBD |
| 1 | Phase 1: Calculated bandwidth, device heuristics | TBD |
| 2 | Phase 1: Integration tests, documentation | TBD |
| 2 | Phase 2: PowerMetricsCollector implementation | TBD |
| 3 | Phase 2: macOS power integration, sudo setup guide | TBD |
| 3 | Phase 2: Power metrics validation | TBD |
| 4 | Phase 3: ANE private API research | TBD |
| 4 | Phase 3: ANEHardwareProfiler implementation | TBD |
| 5 | Phase 3: Testing, risk mitigation, documentation | TBD |
| 5 | Final integration, performance benchmarking | TBD |

---

## References

[1] Terra System Profiler - `Sources/TerraSystemProfiler/TerraSystemProfiler.swift`
- Memory snapshot implementation using `mach_task_basic_info`

[2] espresso - `~/CodingProjects/espresso/`
- `Sources/EspressoBench/ThermalMonitor.swift` - Thermal state monitoring
- `Sources/EspressoGenerate/PowerTelemetry.swift` - powermetrics integration
- `Sources/ANEInterop/ane_interop.m` - ANE private API usage
- `Sources/Espresso/InferenceKernelProfile.swift` - Kernel profiling structure

[3] Apple Developer Documentation
- ProcessInfo.thermalState: https://developer.apple.com/documentation/foundation/processinfo/thermalstate
- mach_absolute_time: https://developer.apple.com/library/archive/qa/qa1398/_index.html

[4] anemll-bench - `https://github.com/Anemll/anemll-bench`
- `anemll_bench/benchmark.py` - Bandwidth calculation, timing heuristics, model size detection

[5] anemll-bench Documentation
- "Understanding Performance Metrics" section from README.md

[6] Apple powermetrics man page
- https://www.unix.com/man-page/macosx/8/powermetrics/

[7] CoreML Documentation
- MLComputeUnits: https://developer.apple.com/documentation/coreml/mlcomputeunits

---

## Appendix A: Model Size Detection Algorithm

```
Input: modelPath (URL to .mlmodelc or .mlpackage)
Output: sizeBytes (UInt64)

1. If modelPath ends with ".mlmodelc":
   a. weightsDir = modelPath + "/weights"
   b. For each file in weightsDir matching "*.bin":
      i. sizeBytes += file.size

2. If modelPath ends with ".mlpackage":
   a. weightsDir = modelPath + "/Data/com.apple.CoreML/weights"
   b. For each file in weightsDir:
      i. sizeBytes += file.size

3. Return sizeBytes
```

**Edge Cases:**
- Model not found: Return nil
- Weights directory missing: Return 0
- Permission denied: Log warning, return nil
- Nested weight files: Recursively sum all files

---

## Appendix B: powermetrics Output Format

```
*** Sampled system activity (Thu Mar 20 12:34:56 2026 -0700) ***

CPU Power: 2345 mW
GPU Power: 1234 mW
ANE Power: 3456 mW
Package Power: 7035 mW
```

**Parsing Regex:**
```
(?im)^\s*(CPU Power|GPU Power|ANE Power|Package Power)\s*:\s*([0-9]+(?:\.[0-9]+)?)\s*(mW|W)\s*$
```

**Unit Conversion:**
- mW -> W: divide by 1000
- W -> mW: multiply by 1000

---

## Appendix C: Thermal State Transition Matrix

| From/To | nominal | fair | serious | critical |
|---------|---------|------|---------|----------|
| nominal | - | Gradual load | Sustained load | Extreme load |
| fair | Idle/cooling | - | Continued load | Thermal emergency |
| serious | Cooling | Reduced load | - | Critical threshold |
| critical | Significant cooling | Throttling | Minimal load | - |

**Implications for Inference:**
- **nominal**: Full performance, no throttling
- **fair**: Up to 10% performance reduction possible
- **serious**: 20-50% throttling likely, sustained inference problematic
- **critical**: >50% throttling, inference should pause if possible

---

*End of Document*
