import Foundation
import OpenTelemetryApi
import TerraSystemProfiler

#if canImport(CoreML)
import CoreML
#endif

public struct CalculatedMetrics: Sendable, TelemetryAttributeConvertible {
  public let modelSize: ModelSizeDetector.ModelSize
  public let inferenceTimeMs: Double

  public var bandwidthGBs: Double {
    guard inferenceTimeMs > 0 else { return 0 }
    let seconds = inferenceTimeMs / 1000
    return Double(modelSize.totalBytes) / (seconds * 1_000_000_000)
  }

  public var telemetryAttributes: [String: AttributeValue] {
    var attrs = modelSize.telemetryAttributes
    attrs["terra.model.bandwidth_gbps"] = .double(bandwidthGBs)
    attrs["terra.model.inference_time_ms"] = .double(inferenceTimeMs)
    return attrs
  }

  public init(modelSize: ModelSizeDetector.ModelSize, inferenceTimeMs: Double) {
    self.modelSize = modelSize
    self.inferenceTimeMs = inferenceTimeMs
  }
}

public enum ComputeDeviceGuess: String, Sendable, TelemetryAttributeConvertible {
  case likelyANE = "likely_ane"
  case likelyGPU = "likely_gpu"
  case likelyCPU = "likely_cpu"
  case unknown

  public var telemetryAttributes: [String: AttributeValue] {
    ["terra.model.compute_device_guess": .string(rawValue)]
  }

  #if canImport(CoreML)
  public init(inferenceTimeMs: Double, computeUnits: MLComputeUnits? = nil) {
    // If explicitly CPU-only, always classify as CPU
    if let units = computeUnits, units == .cpuOnly {
      self = .likelyCPU
      return
    }

    // If explicitly CPU+ANE, bias toward ANE classification
    if let units = computeUnits, units == .cpuAndNeuralEngine {
      self = inferenceTimeMs < 100 ? .likelyANE : .likelyCPU
      return
    }

    // Heuristic thresholds
    if inferenceTimeMs < 20 {
      self = .likelyANE
    } else if inferenceTimeMs < 100 {
      self = .likelyGPU
    } else {
      self = .likelyCPU
    }
  }
  #endif

  public init(inferenceTimeMs: Double) {
    if inferenceTimeMs < 20 {
      self = .likelyANE
    } else if inferenceTimeMs < 100 {
      self = .likelyGPU
    } else {
      self = .likelyCPU
    }
  }
}
