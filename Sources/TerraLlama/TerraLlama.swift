import Foundation
import OpenTelemetryApi
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
    _ body: @Sendable (Terra.StreamingInferenceScope) async throws -> R
  ) async rethrows -> R {
    var request = Terra.InferenceRequest(model: model, prompt: prompt)
    request.stream = true
    return try await Terra.withStreamingInferenceSpan(request) { streamScope in
      streamScope.setAttributes([
        Terra.Keys.Terra.runtime: .string("llama_cpp"),
        Terra.Keys.Terra.autoInstrumented: .bool(true),
      ])
      return try await body(streamScope)
    }
  }

  public static func applyDecodeStats(
    _ stats: DecodeStats,
    to scope: Terra.StreamingInferenceScope
  ) {
    var attributes: [String: AttributeValue] = [:]
    if let tokensPerSecond = stats.tokensPerSecond {
      attributes[Terra.Keys.Terra.streamTokensPerSecond] = .double(tokensPerSecond)
    }
    if let timeToFirstTokenMS = stats.timeToFirstTokenMS {
      attributes[Terra.Keys.Terra.streamTimeToFirstTokenMs] = .double(timeToFirstTokenMS)
    }
    if let kvCacheUsagePercent = stats.kvCacheUsagePercent {
      attributes["terra.llama.kv_cache_usage_percent"] = .double(kvCacheUsagePercent)
    }
    scope.setAttributes(attributes)
  }

  public static func recordLayerMetrics(
    _ metrics: [LayerMetric],
    to scope: Terra.StreamingInferenceScope
  ) {
    for metric in metrics {
      var attributes: [String: AttributeValue] = [
        "terra.llama.layer.name": .string(metric.layerName),
        "terra.llama.layer.duration_ms": .double(metric.durationMS),
      ]
      if let memoryMB = metric.memoryMB {
        attributes["terra.llama.layer.memory_mb"] = .double(memoryMB)
      }
      scope.addEvent("terra.llama.layer.profile", attributes: attributes)
    }
  }
}
