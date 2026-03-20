import Foundation
import OpenTelemetryApi
import TerraSystemProfiler

public enum ModelSizeDetector {

  public enum ModelFormat: String, Sendable {
    case compiledModel = "compiled_model"
    case modelPackage = "model_package"
  }

  public struct ModelSize: Sendable, TelemetryAttributeConvertible {
    public let totalBytes: UInt64
    public let weightFileCount: Int
    public let format: ModelFormat

    public var totalMB: Double {
      Double(totalBytes) / 1_048_576
    }

    public var telemetryAttributes: [String: AttributeValue] {
      [
        "terra.model.size_bytes": .int(Int(totalBytes)),
        "terra.model.size_mb": .double(totalMB),
        "terra.model.weight_file_count": .int(weightFileCount),
        "terra.model.format": .string(format.rawValue),
      ]
    }
  }

  public static func detectSize(of modelURL: URL) -> ModelSize? {
    let path = modelURL.path
    let fm = FileManager.default

    // Try .mlmodelc (compiled model)
    if path.hasSuffix(".mlmodelc") || fm.fileExists(atPath: modelURL.appendingPathComponent("weights").path) {
      return scanWeightsDirectory(
        modelURL.appendingPathComponent("weights"),
        format: .compiledModel
      )
    }

    // Try .mlpackage
    if path.hasSuffix(".mlpackage") {
      let weightsDir = modelURL
        .appendingPathComponent("Data")
        .appendingPathComponent("com.apple.CoreML")
        .appendingPathComponent("weights")
      if fm.fileExists(atPath: weightsDir.path) {
        return scanWeightsDirectory(weightsDir, format: .modelPackage)
      }
    }

    return nil
  }

  private static func scanWeightsDirectory(_ url: URL, format: ModelFormat) -> ModelSize? {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
      at: url,
      includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else { return nil }

    var totalBytes: UInt64 = 0
    var fileCount = 0

    while let fileURL = enumerator.nextObject() as? URL {
      guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
            values.isRegularFile == true,
            let size = values.fileSize
      else { continue }
      totalBytes += UInt64(size)
      fileCount += 1
    }

    guard fileCount > 0 else { return nil }
    return ModelSize(totalBytes: totalBytes, weightFileCount: fileCount, format: format)
  }
}
