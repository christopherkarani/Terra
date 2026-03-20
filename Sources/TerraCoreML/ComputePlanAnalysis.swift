#if canImport(CoreML)
import CoreML
import Foundation
import OpenTelemetryApi
import TerraCore
import TerraSystemProfiler

package struct ComputePlanAnalysis: Sendable, TelemetryAttributeConvertible {
  public let totalOps: Int
  public let aneOps: Int
  public let gpuOps: Int
  public let cpuOps: Int

  public var aneUtilization: Double {
    guard totalOps > 0 else { return 0 }
    return Double(aneOps) / Double(totalOps)
  }

  public var dominantDevice: String {
    if aneOps >= gpuOps && aneOps >= cpuOps { return "ane" }
    if gpuOps >= aneOps && gpuOps >= cpuOps { return "gpu" }
    return "cpu"
  }

  public var isMixedExecution: Bool {
    let devices = [aneOps > 0, gpuOps > 0, cpuOps > 0]
    return devices.filter { $0 }.count > 1
  }

  public var telemetryAttributes: [String: AttributeValue] {
    [
      "terra.compute_plan.total_ops": .int(totalOps),
      "terra.compute_plan.ane_ops": .int(aneOps),
      "terra.compute_plan.gpu_ops": .int(gpuOps),
      "terra.compute_plan.cpu_ops": .int(cpuOps),
      "terra.compute_plan.ane_utilization": .double(aneUtilization),
      "terra.compute_plan.dominant_device": .string(dominantDevice),
      "terra.compute_plan.is_mixed_execution": .bool(isMixedExecution),
    ]
  }

  package static func analyze(_ summary: TerraCoreMLComputePlanSummary) -> ComputePlanAnalysis {
    var ane = 0
    var gpu = 0
    var cpu = 0

    for op in summary.operationEstimates {
      switch op.preferredDevice {
      case "ane": ane += 1
      case "gpu": gpu += 1
      case "cpu": cpu += 1
      default: break
      }
    }

    return ComputePlanAnalysis(
      totalOps: summary.operationEstimates.count,
      aneOps: ane,
      gpuOps: gpu,
      cpuOps: cpu
    )
  }

  public func assessANEFallback(observedInferenceTimeMs: Double) -> ANEFallbackAssessment {
    // If ANE utilization is high but inference is slow, ANE fallback likely occurred
    let highANERatio = aneUtilization > 0.5
    let slowForANE = observedInferenceTimeMs > 50

    if highANERatio && slowForANE {
      return ANEFallbackAssessment(
        isFallbackLikely: true,
        confidence: aneUtilization > 0.8 ? .high : .medium
      )
    }

    return ANEFallbackAssessment(
      isFallbackLikely: false,
      confidence: highANERatio ? .medium : .low
    )
  }
}

package struct ANEFallbackAssessment: Sendable, TelemetryAttributeConvertible {
  package let isFallbackLikely: Bool
  package let confidence: Terra.ExecutionRouteConfidence

  public var telemetryAttributes: [String: AttributeValue] {
    [
      "terra.ane.fallback_likely": .bool(isFallbackLikely),
      "terra.ane.fallback_confidence": .string(confidence.rawValue),
    ]
  }
}
#endif
