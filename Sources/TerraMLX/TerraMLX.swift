import Foundation
import TerraCore
import OpenTelemetryApi

/// Traced wrapper for MLX-based text generation.
/// Users own the mlx-swift call inside the closure; Terra creates the span.
public enum TerraMLX {

  /// Run any MLX generation wrapped in a Terra inference span.
  ///
  /// Usage:
  /// ```swift
  /// let result = try await TerraMLX.traced(model: "mlx-community/Llama-3.2-1B", maxTokens: 256) {
  ///   // Your mlx-swift generation code here
  ///   return resultString
  /// }
  /// ```
  @discardableResult
  public static func traced<R>(
    model: String,
    maxTokens: Int? = nil,
    temperature: Double? = nil,
    device: String? = nil,
    memoryFootprintMB: Double? = nil,
    modelLoadDurationMS: Double? = nil,
    _ body: @Sendable () async throws -> R
  ) async throws -> R {
    let request = Terra.InferenceRequest(
      model: model,
      maxOutputTokens: maxTokens,
      temperature: temperature
    )
    return try await Terra.withInferenceSpan(request) { scope in
      var attributes: [String: AttributeValue] = [
        Terra.Keys.Terra.runtime: .string("mlx"),
        Terra.Keys.Terra.autoInstrumented: .bool(true)
      ]
      if let device {
        attributes["terra.mlx.device"] = .string(device)
      }
      if let memoryFootprintMB {
        attributes["terra.mlx.memory_footprint_mb"] = .double(memoryFootprintMB)
      }
      if let modelLoadDurationMS {
        attributes["terra.mlx.model_load_duration_ms"] = .double(modelLoadDurationMS)
      }
      scope.setAttributes(attributes)
      return try await body()
    }
  }

  /// Record the first-token event on the current active Terra span.
  /// Call from inside your mlx-swift `didGenerate` callback when token count == 1.
  public static func recordFirstToken() {
    guard let span = OpenTelemetry.instance.contextProvider.activeSpan else { return }
    span.addEvent(name: "terra.first_token")
  }

  /// Record token generation progress on the current active span.
  /// Call periodically from `didGenerate` to track generation progress.
  public static func recordTokenCount(_ count: Int) {
    guard let span = OpenTelemetry.instance.contextProvider.activeSpan else { return }
    span.setAttribute(key: Terra.Keys.GenAI.usageOutputTokens, value: .int(count))
  }
}
