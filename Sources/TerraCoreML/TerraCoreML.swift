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
}

public extension Terra.Scope {
  func setCoreMLAttributes(computeUnits: MLComputeUnits) {
    setAttributes(TerraCoreML.attributes(computeUnits: computeUnits))
  }

  func setCoreMLAttributes(configuration: MLModelConfiguration) {
    setAttributes(TerraCoreML.attributes(configuration: configuration))
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

