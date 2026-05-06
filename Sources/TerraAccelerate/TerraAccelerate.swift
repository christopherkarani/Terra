import Foundation
import OpenTelemetryApi

public enum TerraAccelerate {
  public enum Keys {
    public static let backend = "accelerate.backend"
    public static let operation = "accelerate.operation"
    public static let durationMS = "accelerate.duration_ms"
  }

  public static func attributes(
    backend: String,
    operation: String,
    durationMS: Double
  ) -> [String: AttributeValue] {
    [
      Keys.backend: .string(backend),
      Keys.operation: .string(operation),
      Keys.durationMS: .double(durationMS),
    ]
  }
}
