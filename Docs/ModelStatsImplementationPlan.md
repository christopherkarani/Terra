# Terra Model Stats Implementation Plan

**Version:** 2.0  
**Date:** March 20, 2026  
**Status:** Ready for Implementation  
**Distribution:** macOS/iOS Apps (No App Store Restrictions)

---

## Overview

This document outlines the complete implementation plan for enhancing Terra with comprehensive model performance statistics. The plan is designed for **macOS and iOS app distribution outside the App Store**, with optional App Store compatibility via compiler flags.

### Distribution Strategy

| Build Type | Private APIs | Availability |
|------------|--------------|--------------|
| **macOS App** | ✅ Enabled | Direct distribution, Developer ID |
| **iOS App (Enterprise/Side-load)** | ✅ Enabled | Enterprise certificate, TestFlight internal |
| **iOS App Store** | ❌ Disabled | `#if !APP_STORE` guards required |

---

## Phase 1: Public API Metrics (App Store Safe)

**Status:** Foundation - Works on all platforms  
**Risk:** None  
**Timeline:** Week 1

| Feature | API | Implementation | iOS App Store |
|---------|-----|----------------|---------------|
| **Thermal monitoring** | `ProcessInfo.thermalState` | Sample at 1-second intervals during inference | ✅ Available |
| **Model size detection** | File system scan | Scan `.mlmodelc/weights/*.bin` or `.mlpackage/Data/com.apple.CoreML/weights/` | ✅ Available |
| **Calculated bandwidth** | Derived metric | `model_size_gb / inference_time_s` | ✅ Available |
| **Compute device guess** | Timing heuristics | `<20ms`=ANE, `20-100ms`=GPU, `>100ms`=CPU | ✅ Available |
| **High-precision timing** | `mach_absolute_time()` | Darwin kernel, nanosecond precision | ✅ Available |

### Implementation Details

```swift
// Sources/TerraSystemProfiler/ThermalMonitor.swift
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

```swift
// Sources/TerraCoreML/ModelSizeDetector.swift
public enum ModelSizeDetector {
    public static func detectSize(of modelURL: URL) -> UInt64?
    // Scans:
    // - .mlmodelc/weights/*.bin (compiled model weights)
    // - .mlpackage/Data/com.apple.CoreML/weights/* (package weights)
}
```

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

## Phase 2: MLComputePlan Analysis (macOS 14+/iOS 17+)

**Status:** Public API, Newer OS Only  
**Risk:** None  
**Timeline:** Week 2

| Feature | API | Implementation | iOS App Store |
|---------|-----|----------------|---------------|
| **Per-operation device placement** | `MLComputePlan` | `computeDeviceUsageForMLProgramOperation()` | ✅ Available (iOS 17+) |
| **ANE utilization %** | Compute plan stats | `ane_ops / total_ops` | ✅ Available |
| **Per-op cost weights** | `MLComputePlanCost` | Relative performance estimates | ✅ Available |
| **ANE fallback detection** | Timing comparison | Detect runtime CPU fallback | ✅ Available |

### Implementation Details

```swift
// Sources/TerraCoreML/ComputePlanAnalyzer.swift
@available(macOS 14.0, iOS 17.0, *)
public struct ComputePlanAnalysis: Sendable {
    public let totalOps: Int
    public let aneOps: Int
    public let cpuOps: Int
    public let gpuOps: Int
    public let aneCostPercentage: Double
    
    public struct OpPlacement: Sendable {
        public let name: String
        public let type: String
        public let device: ComputeDevice
        public let estimatedRuntimeMs: Double
    }
    public let perOpPlacements: [OpPlacement]
    
    public var aneUtilization: Double {
        Double(aneOps) / Double(totalOps)
    }
}

@available(macOS 14.0, iOS 17.0, *)
public final class ComputePlanAnalyzer {
    public static func analyze(modelURL: URL, configuration: MLModelConfiguration) async throws -> ComputePlanAnalysis
}
```

---

## Phase 3: Espresso Log Capture (macOS)

**Status:** Public Tool, macOS Only  
**Risk:** None (uses `/usr/bin/log`)  
**Timeline:** Week 2-3

| Feature | Source | Implementation | iOS App Store |
|---------|--------|----------------|---------------|
| **Per-op GFLOP/s estimates** | `log stream` Espresso | Parse `CostModelFeature` entries | ❌ Not available |
| **Memory vs Compute bound** | `Bound:Memory/Compute` | Bottleneck classification | ❌ Not available |
| **ANE work unit efficiency** | `workUnitEfficiency16` | ANE utilization estimate | ❌ Not available |
| **Total GFLOP count** | `gFlopCnt` sum | Model complexity metric | ❌ Not available |

### Implementation Details

```swift
// Sources/TerraCoreML/EspressoLogCapture.swift
#if os(macOS)
import Foundation

@available(macOS 14.0, *)
public final class EspressoLogCapture: @unchecked Sendable {
    private var process: Process?
    private var logPath: String?
    
    public func start() throws
    public func stop() -> [CostModelEntry]
}

public struct CostModelEntry: Sendable {
    public let name: String
    public let type: String
    public let gFlopCnt: Double
    public let gflops: Double
    public let gbps: Double
    public let runtimeMs: Double
    public let isMemoryBound: Bool
    public let workUnitEfficiency: Double
}
#endif
```

### Log Capture Process

```
/usr/bin/log stream \
    --predicate "subsystem == \"com.apple.espresso\"" \
    --info --debug --style compact
```

### Sample CostModelFeature Log Line

```
[CostModelFeature],op_name,ios18.conv,gFlopCnt,2.45,totalMB,4.32,
    mbKernel,1.23,opsPerByte,12.3,workUnitEfficiency16,0.85,
    GFLOP/s,45.2,GBP/s,23.4,Runtime,0.054,Bound:Memory
```

---

## Phase 4: Power Metrics (macOS, Requires Sudo)

**Status:** External Tool, macOS Only  
**Risk:** Low (requires setup)  
**Timeline:** Week 3

| Feature | Source | Implementation | iOS App Store |
|---------|--------|----------------|---------------|
| **CPU power (Watts)** | `powermetrics` | `--samplers cpu_power` | ❌ Not available |
| **GPU power (Watts)** | `powermetrics` | `--samplers gpu_power` | ❌ Not available |
| **ANE power (Watts)** | `powermetrics` | `--samplers ane_power` | ❌ Not available |
| **Package power (Watts)** | `powermetrics` | Total SoC power | ❌ Not available |

### Implementation Details

```swift
// Sources/TerraPowerProfiler/PowerMetricsCollector.swift
#if os(macOS)
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

### Setup Requirements

```bash
# User must configure passwordless sudo for powermetrics
sudo visudo
# Add line:
%admin ALL=(ALL) NOPASSWD: /usr/bin/powermetrics
```

---

## Phase 5: Private AppleNeuralEngine Framework ⚠️

**Status:** Private API - APP STORE INCOMPATIBLE  
**Risk:** High - Will fail App Store review  
**Timeline:** Week 4  
**Guard:** `#if !APP_STORE`

| Feature | Source | Risk | Implementation |
|---------|--------|------|----------------|
| **Runtime ANE segment detection** | Method swizzling (`ANECompat`) | High - runtime code modification | Intercept `AppleNeuralEngine` framework |
| **ANE hardware execution time** | `_ANEPerformanceStats` | Medium - private class | Hardware-reported execution nanoseconds |
| **Actual vs estimated runtime** | Swizzled eval | High - framework tampering | Ground truth for all other metrics |

### ⚠️ App Store Warning

```swift
// Sources/TerraANEProfiler/ANEHardwareProfiler.swift
#if !APP_STORE
import Foundation

public final class ANEHardwareProfiler: @unchecked Sendable {
    public func startProfiling()
    public func stopProfiling() -> ANEHardwareMetrics
}

public struct ANEHardwareMetrics: Sendable {
    public let hardwareExecutionTimeNs: UInt64
    public let hostOverheadUs: Double
    public let totalEvalTimeUs: Double
    public let aneSegments: [ANESegment]
    
    public struct ANESegment: Sendable {
        public let segmentIndex: Int
        public let inputs: [String: ANETensorInfo]
        public let outputs: [String: ANETensorInfo]
    }
    
    public struct ANETensorInfo: Sendable {
        public let shape: [Int]
    }
}

// Runtime warning
public func checkANEPrivateAPIAvailability() {
    #if ANE_PRIVATE_APIS_ENABLED && !APP_STORE
    logger.warning("""
        ⚠️  ANE Private APIs Enabled
        
        This build provides accurate runtime ANE detection via method swizzling 
        and private framework access. This makes your app INELIGIBLE for 
        App Store distribution.
        
        For App Store builds, compile with:
            swift build -Xswiftc -DAPP_STORE
        
        Or in Package.swift:
            .define("APP_STORE", .when(configuration: .release))
        """)
    #endif
}
#endif
```

### Method Swizzling Approach (from ANECompat)

```objc
// Objective-C runtime swizzling
// Intercepts evaluation methods in AppleNeuralEngine framework

static void swizzleMethods(Class class, SEL originalSelector, SEL swizzledSelector) {
    Method originalMethod = class_getInstanceMethod(class, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
    method_exchangeImplementations(originalMethod, swizzledMethod);
}

// Detect ANE segment execution at runtime
// Returns: 0 = Full ANE, 1 = Partial ANE, 2 = No ANE
```

---

## Compiler Configuration

### Package.swift Settings

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Terra",
    // ...
    targets: [
        .target(
            name: "Terra",
            dependencies: [/* ... */],
            swiftSettings: [
                // App Store builds: Disable private APIs
                .define("APP_STORE", .when(configuration: .release)),
                
                // Enable private ANE APIs for macOS/iOS builds
                .define("ANE_PRIVATE_APIS_ENABLED", .when(platforms: [.macOS, .iOS])),
                
                // Disable private APIs explicitly for App Store
                .define("DISABLE_ANE_PRIVATE_APIS", .when(configuration: .release)),
            ]
        )
    ]
)
```

### Build Configurations

```bash
# macOS / iOS (Enterprise/Side-load) - Full features
swift build

# iOS App Store - App Store Safe only
swift build -Xswiftc -DAPP_STORE

# Explicit disable
swift build -Xswiftc -DDISABLE_ANE_PRIVATE_APIS
```

---

## App Store Compatibility Matrix

| Feature | macOS App | iOS Enterprise | iOS App Store | Implementation |
|---------|-----------|----------------|---------------|----------------|
| Thermal monitoring | ✅ | ✅ | ✅ | Public API |
| Model size detection | ✅ | ✅ | ✅ | File system |
| Calculated bandwidth | ✅ | ✅ | ✅ | Derived |
| Compute device guess | ✅ | ✅ | ✅ | Heuristics |
| MLComputePlan | ✅ | ✅ (17+) | ✅ (17+) | Public API |
| Espresso logs | ✅ | ❌ | ❌ | macOS only |
| Power metrics | ✅ | ❌ | ❌ | macOS only |
| **ANE swizzling** | ✅ | ✅ | ❌ `#if !APP_STORE` | Private API |
| **ANE hardware time** | ✅ | ✅ | ❌ `#if !APP_STORE` | Private API |

---

## New OpenTelemetry Semantic Conventions

```swift
// Model metadata
model.size.bytes                    // UInt64
model.bandwidth.gbps               // Double - Calculated
model.compute_device.guess         // String - likely_ane/likely_gpu/likely_cpu

// Thermal
temperature.thermal_state          // String - nominal/fair/serious/critical
temperature.peak_state             // String - Highest during inference
temperature.time_in_throttle       // Double - Seconds in serious/critical

// Compute plan (macOS 14+/iOS 17+)
compute_plan.total_ops             // Int
compute_plan.ane_ops               // Int
compute_plan.ane_ops.percentage    // Double - 0.0 to 1.0
compute_plan.cpu_ops               // Int
compute_plan.gpu_ops               // Int
compute_plan.per_op_placement[]    // Array of op placements

// Espresso logs (macOS only)
espresso.estimated_gflops_per_op[] // [Double]
espresso.estimated_gbps_per_op[]   // [Double]
espresso.memory_bound_ops[]        // [String] - Op names
espresso.compute_bound_ops[]       // [String] - Op names
espresso.ane_work_unit_efficiency  // Double - 0.0 to 1.0
espresso.total_gflops              // Double - Sum of gFlopCnt

// Power (macOS only)
power.cpu.watts                    // Double
power.gpu.watts                    // Double
power.ane.watts                    // Double
power.package.watts                // Double
power.sample_duration_ms           // Double

// ANE Hardware (Private API - macOS/iOS only)
ane.hardware_execution_time.ns     // UInt64
ane.host_overhead.us               // Double
ane.segments.count                 // Int
ane.segments.fully_ane             // Bool
```

---

## Module Structure

```
Sources/
├── Terra/
│   ├── Terra.swift                    # Main API
│   ├── ModelStats.swift               # Unified stats interface
│   └── OpenTelemetryExtensions.swift  # Semantic conventions
│
├── TerraSystemProfiler/
│   ├── TerraSystemProfiler.swift      # Existing
│   ├── ThermalMonitor.swift           # Phase 1
│   └── MachTime.swift                 # High-precision timing
│
├── TerraCoreML/
│   ├── TerraCoreML.swift              # Existing
│   ├── ModelSizeDetector.swift        # Phase 1
│   ├── CalculatedMetrics.swift        # Phase 1
│   ├── ComputePlanAnalyzer.swift      # Phase 2
│   └── EspressoLogCapture.swift       # Phase 3 (macOS)
│
├── TerraPowerProfiler/                # Phase 4 (macOS only)
│   └── PowerMetricsCollector.swift
│
└── TerraANEProfiler/                  # Phase 5 (Private API)
    ├── ANEHardwareProfiler.swift
    ├── ANESwizzling.m                 # Objective-C runtime
    └── ANECompatBridge.swift
```

---

## User Documentation: Distribution Warnings

```markdown
## App Store Distribution Notice

Terra Model Stats includes features that use private Apple frameworks 
and runtime code modification. These features are automatically 
disabled for App Store builds.

### Feature Availability

| Build Type | ANE Runtime Detection | Power Metrics |
|------------|----------------------|---------------|
| macOS App | ✅ Full | ✅ Full |
| iOS Enterprise | ✅ Full | ❌ macOS only |
| iOS App Store | ⚠️ Estimated only | ❌ Unavailable |

### Building for App Store

Add to your Package.swift or build command:

    swift build -Xswiftc -DAPP_STORE

This disables:
- Method swizzling for ANE detection
- Private `_ANEPerformanceStats` access

### Runtime Warning

When using private API features, Terra logs:

    ⚠️ ANE Private APIs Enabled - Not App Store compatible
```

---

## Implementation Timeline

| Week | Phase | Deliverables |
|------|-------|--------------|
| 1 | Phase 1 | Thermal monitoring, model size detection, calculated bandwidth, device heuristics |
| 2 | Phase 2 | MLComputePlan analyzer, per-op device placement |
| 2-3 | Phase 3 | Espresso log capture, CostModelFeature parsing |
| 3 | Phase 4 | Power metrics collector, powermetrics integration |
| 4 | Phase 5 | ANE swizzling, hardware execution time, App Store guards |
| 5 | Integration | Unified API, documentation, testing |

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Thermal coverage | 100% | All inference traces include thermal state |
| Bandwidth accuracy | Within 10% | Compare to chip specs |
| Device guess accuracy | 85% | Manual verification |
| Compute plan availability | 90% (macOS 14+) | Success rate |
| Espresso log capture | 95% (macOS) | Parse success rate |
| Power metric availability | 90% (macOS with sudo) | Success rate |
| ANE hardware time | 95% (Private API) | Success rate |
| Performance overhead | < 5% | Benchmark comparison |

---

## References

### Source Code References

1. **Terra** - `~/CodingProjects/Terra/`
   - Existing instrumentation framework
   - OpenTelemetry integration
   - Memory profiling via `mach_task_basic_info`

2. **espresso** - `~/CodingProjects/espresso/`
   - Power telemetry via `powermetrics`
   - ANE interop via `_ANEPerformanceStats`
   - Thermal monitoring implementation

3. **anemll-bench** - `https://github.com/Anemll/anemll-bench`
   - Bandwidth calculation: `model_size / time`
   - Timing heuristics for device detection
   - Model size detection from CoreML bundles

4. **anemll-profile** - `https://github.com/Anemll/anemll-profile`
   - `anemll_profile.m` - MLComputePlan parsing
   - Espresso log capture via `log stream`
   - CostModelFeature parsing

5. **ANECompat** - `https://github.com/fredyshox/ANECompat`
   - Method swizzling for ANE detection
   - Runtime segment interception
   - Model key JSON structure

### Apple Documentation

6. **ProcessInfo.thermalState** - https://developer.apple.com/documentation/foundation/processinfo/thermalstate
7. **MLComputePlan** - https://developer.apple.com/documentation/coreml/mlcomputeplan
8. **mach_absolute_time** - https://developer.apple.com/library/archive/qa/qa1398/_index.html
9. **powermetrics** - macOS man page

---

## Risk Assessment

| Phase | Risk | Likelihood | Impact | Mitigation |
|-------|------|------------|--------|------------|
| 1 | API availability on older OS | Medium | Low | `@available` checks |
| 2 | MLComputePlan latency | Low | Low | Async loading |
| 3 | Log parsing failures | Medium | Medium | Graceful degradation |
| 4 | sudo requirements | High | Low | Document setup |
| 5 | App Store rejection | High | High | Compiler flags, warnings |
| 5 | Private API changes | Medium | Medium | Runtime probing |

---

*Document Version 2.0 - March 20, 2026*  
*Ready for Implementation*
