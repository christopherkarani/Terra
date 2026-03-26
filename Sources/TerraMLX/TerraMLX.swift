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
    _ body: @escaping @Sendable () async throws -> R
  ) async throws -> R {
    let request = Terra.InferenceRequest(
      model: model,
      maxOutputTokens: maxTokens,
      temperature: temperature
    )
    var call = Terra
      .inference(request)
      .provider("mlx")
      .runtime("mlx")
      .attribute(.init(Terra.Keys.Terra.autoInstrumented), true)

    if let device {
      call = call.attribute(.init("terra.mlx.device"), device)
    }
    if let memoryFootprintMB {
      call = call.attribute(.init("terra.mlx.memory_footprint_mb"), memoryFootprintMB)
    }
    if let modelLoadDurationMS {
      call = call.attribute(.init("terra.mlx.model_load_duration_ms"), modelLoadDurationMS)
    }

    return try await call.execute {
      try await body()
    }
  }

  @available(*, deprecated, message: "Use String model names directly.")
  @discardableResult
  public static func traced<R>(
    model: Terra.ModelID,
    maxTokens: Int? = nil,
    temperature: Double? = nil,
    device: String? = nil,
    memoryFootprintMB: Double? = nil,
    modelLoadDurationMS: Double? = nil,
    _ body: @escaping @Sendable () async throws -> R
  ) async throws -> R {
    try await traced(
      model: model.rawValue,
      maxTokens: maxTokens,
      temperature: temperature,
      device: device,
      memoryFootprintMB: memoryFootprintMB,
      modelLoadDurationMS: modelLoadDurationMS,
      body
    )
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
