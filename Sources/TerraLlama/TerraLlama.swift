import Foundation
import TerraCore

public enum TerraLlama {
  public struct DecodeStats: Sendable {
    public var tokensPerSecond: Double?
    public var timeToFirstTokenMS: Double?
    public var kvCacheUsagePercent: Double?

    public init(
      tokensPerSecond: Double? = nil,
      timeToFirstTokenMS: Double? = nil,
      kvCacheUsagePercent: Double? = nil
    ) {
      self.tokensPerSecond = tokensPerSecond
      self.timeToFirstTokenMS = timeToFirstTokenMS
      self.kvCacheUsagePercent = kvCacheUsagePercent
    }
  }

  public struct LayerMetric: Sendable {
    public var layerName: String
    public var durationMS: Double
    public var memoryMB: Double?

    public init(layerName: String, durationMS: Double, memoryMB: Double? = nil) {
      self.layerName = layerName
      self.durationMS = durationMS
      self.memoryMB = memoryMB
    }
  }

  @discardableResult
  public static func traced<R>(
    model: String,
    prompt: String? = nil,
    _ body: @Sendable (Terra.StreamingTrace) async throws -> R
  ) async rethrows -> R {
    let request = Terra.StreamingRequest(model: model, prompt: prompt)
    return try await Terra
      .stream(request)
      .provider("llama.cpp")
      .runtime("llama_cpp")
      .attribute(.init(Terra.Keys.Terra.autoInstrumented), true)
      .execute { trace in
        try await body(trace)
      }
  }

  public static func applyDecodeStats(
    _ stats: DecodeStats,
    to scope: Terra.StreamingTrace
  ) {
    if let tokensPerSecond = stats.tokensPerSecond {
      scope.attribute(.init(Terra.Keys.Terra.streamTokensPerSecond), tokensPerSecond)
    }
    if let timeToFirstTokenMS = stats.timeToFirstTokenMS {
      scope.attribute(.init(Terra.Keys.Terra.streamTimeToFirstTokenMs), timeToFirstTokenMS)
    }
    if let kvCacheUsagePercent = stats.kvCacheUsagePercent {
      scope.attribute(.init("terra.llama.kv_cache_usage_percent"), kvCacheUsagePercent)
    }
  }

  public static func recordLayerMetrics(
    _ metrics: [LayerMetric],
    to scope: Terra.StreamingTrace
  ) {
    for metric in metrics {
      scope.emit(LayerProfileEvent(
        layerName: metric.layerName,
        durationMS: metric.durationMS,
        memoryMB: metric.memoryMB
      ))
    }
  }

  private struct LayerProfileEvent: Terra.TerraEvent {
    static var name: StaticString { "terra.llama.layer.profile" }

    let layerName: String
    let durationMS: Double
    let memoryMB: Double?

    func encode(into attributes: inout Terra.AttributeBag) {
      attributes.set(.init("terra.llama.layer.name"), layerName)
      attributes.set(.init("terra.llama.layer.duration_ms"), durationMS)
      if let memoryMB {
        attributes.set(.init("terra.llama.layer.memory_mb"), memoryMB)
      }
    }
  }
}
