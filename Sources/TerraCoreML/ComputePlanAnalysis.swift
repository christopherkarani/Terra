#if canImport(CoreML)
import CoreML
import Foundation
import OpenTelemetryApi
import TerraCore
import TerraSystemProfiler

package struct ComputePlanAnalysis: Sendable, TelemetryAttributeConvertible {
  package let totalOps: Int
  package let aneOps: Int
  package let gpuOps: Int
  package let cpuOps: Int

  package var aneUtilization: Double {
    guard totalOps > 0 else { return 0 }
    return Double(aneOps) / Double(totalOps)
  }

  package var dominantDevice: String {
    if aneOps >= gpuOps && aneOps >= cpuOps { return "ane" }
    if gpuOps >= aneOps && gpuOps >= cpuOps { return "gpu" }
    return "cpu"
  }

  package var isMixedExecution: Bool {
    (aneOps > 0 ? 1 : 0) + (gpuOps > 0 ? 1 : 0) + (cpuOps > 0 ? 1 : 0) > 1
  }

  package var telemetryAttributes: [String: AttributeValue] {
    [
      Terra.Keys.Terra.computePlanTotalOps: .int(totalOps),
      Terra.Keys.Terra.computePlanAneOps: .int(aneOps),
      Terra.Keys.Terra.computePlanGpuOps: .int(gpuOps),
      Terra.Keys.Terra.computePlanCpuOps: .int(cpuOps),
      Terra.Keys.Terra.computePlanAneUtilization: .double(aneUtilization),
      Terra.Keys.Terra.computePlanDominantDevice: .string(dominantDevice),
      Terra.Keys.Terra.computePlanIsMixedExecution: .bool(isMixedExecution),
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

  package func assessANEFallback(observedInferenceTimeMs: Double) -> ANEFallbackAssessment {
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

  package var telemetryAttributes: [String: AttributeValue] {
    [
      Terra.Keys.Terra.aneFallbackLikely: .bool(isFallbackLikely),
      Terra.Keys.Terra.aneFallbackConfidence: .string(confidence.rawValue),
    ]
  }
}
#endif
