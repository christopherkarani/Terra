import Foundation
import TerraCore
import OpenTelemetryApi

/// Traced wrapper for MLX-based text generation.
/// Users own the mlx-swift call inside the closure; Terra creates the span.
public enum TerraMLX {
  public struct StreamingTrace: Sendable {
    private let recordFirstToken: @Sendable () -> Void
    private let recordChunk: @Sendable (Int?) -> Void
    private let recordOutputTokens: @Sendable (Int) -> Void
    private let recordStringAttribute: @Sendable (String, String) -> Void
    private let recordIntAttribute: @Sendable (String, Int) -> Void
    private let recordDoubleAttribute: @Sendable (String, Double) -> Void
    private let recordBoolAttribute: @Sendable (String, Bool) -> Void

    package init(_ trace: Terra.StreamingTrace) {
      recordFirstToken = { trace.firstToken() }
      recordChunk = { tokens in
        if let tokens {
          trace.chunk(tokens: tokens)
        } else {
          trace.chunk()
        }
      }
      recordOutputTokens = { tokens in trace.outputTokens(tokens) }
      recordStringAttribute = { key, value in trace.attribute(.init(key), value) }
      recordIntAttribute = { key, value in trace.attribute(.init(key), value) }
      recordDoubleAttribute = { key, value in trace.attribute(.init(key), value) }
      recordBoolAttribute = { key, value in trace.attribute(.init(key), value) }
    }

    public func firstToken() {
      recordFirstToken()
    }

    public func chunk(tokens: Int? = nil) {
      recordChunk(tokens)
    }

    public func outputTokens(_ count: Int) {
      recordOutputTokens(count)
    }

    public func attribute(_ key: String, _ value: String) {
      recordStringAttribute(key, value)
    }

    public func attribute(_ key: String, _ value: Int) {
      recordIntAttribute(key, value)
    }

    public func attribute(_ key: String, _ value: Double) {
      recordDoubleAttribute(key, value)
    }

    public func attribute(_ key: String, _ value: Bool) {
      recordBoolAttribute(key, value)
    }
  }

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

  /// Run MLX streaming generation inside Terra's streaming span lifecycle.
  ///
  /// Use this when the caller can report first-token, chunk, or output-token
  /// progress from the underlying MLX generation loop.
  @discardableResult
  public static func tracedStream<R>(
    model: String,
    prompt: String? = nil,
    maxTokens: Int? = nil,
    temperature: Double? = nil,
    device: String? = nil,
    memoryFootprintMB: Double? = nil,
    modelLoadDurationMS: Double? = nil,
    _ body: @escaping @Sendable (StreamingTrace) async throws -> R
  ) async throws -> R {
    let request = Terra.StreamingRequest(
      model: model,
      prompt: prompt,
      maxOutputTokens: maxTokens,
      temperature: temperature
    )
    var call = Terra
      .stream(request)
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

    return try await call.execute { trace in
      try await body(StreamingTrace(trace))
    }
  }

  /// Record the first-token event on the current active Terra span.
  /// Call from inside your mlx-swift `didGenerate` callback when token count == 1.
  public static func recordFirstToken() {
    if let span = Terra.currentSpan(), !span.isEnded {
      span.event(Terra.Keys.Terra.streamFirstTokenEvent)
      return
    }
    guard let span = OpenTelemetry.instance.contextProvider.activeSpan else { return }
    span.addEvent(name: Terra.Keys.Terra.streamFirstTokenEvent)
  }

  /// Record token generation progress on the current active span.
  /// Call periodically from `didGenerate` to track generation progress.
  public static func recordTokenCount(_ count: Int) {
    guard count >= 0 else { return }
    if let span = Terra.currentSpan(), !span.isEnded {
      span.attribute(Terra.Keys.GenAI.usageOutputTokens, count)
      return
    }
    guard let span = OpenTelemetry.instance.contextProvider.activeSpan else { return }
    span.setAttribute(key: Terra.Keys.GenAI.usageOutputTokens, value: .int(count))
  }
}
