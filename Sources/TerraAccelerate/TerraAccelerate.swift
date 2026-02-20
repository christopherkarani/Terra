import Foundation
import OpenTelemetryApi

public enum TerraAccelerate {
  public static func attributes(
    backend: String,
    operation: String,
    durationMS: Double
  ) -> [String: AttributeValue] {
    [
      "accelerate.backend": .string(backend),
      "accelerate.operation": .string(operation),
      "accelerate.duration_ms": .double(durationMS),
    ]
  }
}
