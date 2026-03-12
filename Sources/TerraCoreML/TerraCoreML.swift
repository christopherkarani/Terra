import OpenTelemetryApi
import TerraCore

#if canImport(CoreML)
import CoreML

/// Optional helpers for attaching Core ML metadata to Terra spans without polluting Terra's core API.
public enum TerraCoreML {
  public enum Keys {
    /// Backend/runtime identifier for the active span.
    public static let runtime = "terra.runtime"
    /// The configured Core ML compute units (from `MLModelConfiguration`).
    public static let computeUnits = "terra.coreml.compute_units"

    // MARK: - Compute Plan keys (package-scoped)
    package static let computePlanCaptureStatus = "terra.coreml.compute_plan.capture_status"
    package static let computePlanModelStructure = "terra.coreml.compute_plan.model_structure"
    package static let computePlanEstimatedPrimaryDevice = "terra.coreml.compute_plan.estimated_primary_device"
    package static let computePlanSupportedDevices = "terra.coreml.compute_plan.supported_devices"
    package static let computePlanNodeCount = "terra.coreml.compute_plan.node_count"
    package static let computePlanCaptureDurationMs = "terra.coreml.compute_plan.capture_duration_ms"
    package static let computePlanEstimatedOperations = "terra.coreml.compute_plan.estimated_operations"
    package static let computePlanErrorType = "terra.coreml.compute_plan.error_type"
  }

  public static func attributes(computeUnits: MLComputeUnits) -> [String: AttributeValue] {
    [
      Keys.runtime: .string("coreml"),
      Keys.computeUnits: .string(computeUnits.terraLabel),
    ]
  }

  public static func attributes(configuration: MLModelConfiguration) -> [String: AttributeValue] {
    attributes(computeUnits: configuration.computeUnits)
  }

  /// Builds route-evidence attributes for a Core ML compute-units selection.
  package static func routeEvidence(
    computeUnits: MLComputeUnits,
    captureMode: Terra.ExecutionRouteCaptureMode,
    confidence: Terra.ExecutionRouteConfidence
  ) -> Terra.ExecutionRouteEvidence {
    let requested: String
    switch computeUnits {
    case .all: requested = "all"
    case .cpuOnly: requested = "cpu"
    case .cpuAndGPU: requested = "cpu_gpu"
    case .cpuAndNeuralEngine: requested = "cpu_ane"
    @unknown default: requested = "unknown"
    }
    return Terra.ExecutionRouteEvidence(
      requested: requested,
      captureMode: captureMode,
      confidence: confidence
    )
  }
}

package extension Terra.InferenceTrace {
  @discardableResult
  func coreML(computeUnits: MLComputeUnits) -> Self {
    attribute(.init(TerraCoreML.Keys.runtime), "coreml")
      .attribute(.init(TerraCoreML.Keys.computeUnits), computeUnits.terraLabel)
  }

  @discardableResult
  func coreML(configuration: MLModelConfiguration) -> Self {
    coreML(computeUnits: configuration.computeUnits)
  }
}

extension MLComputeUnits {
  internal var terraLabel: String {
    switch self {
    case .all:
      return "all"
    case .cpuOnly:
      return "cpu_only"
    case .cpuAndGPU:
      return "cpu_and_gpu"
    case .cpuAndNeuralEngine:
      return "cpu_and_ane"
    @unknown default:
      return "unknown"
    }
  }
}
#else
/// Optional helpers for attaching Core ML metadata to Terra spans without polluting Terra's core API.
///
/// When `CoreML` cannot be imported, this type is still present so client code can compile with
/// conditional imports, but no Core ML-specific helpers are available.
public enum TerraCoreML {}
#endif
