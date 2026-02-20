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
        Terra.Keys.Terra.runtime: .string(Terra.RuntimeKind.llamaCpp.rawValue),
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
      attributes["llama.tokens_per_second"] = .double(tokensPerSecond)
    }
    if let timeToFirstTokenMS = stats.timeToFirstTokenMS {
      attributes["llama.time_to_first_token_ms"] = .double(timeToFirstTokenMS)
    }
    if let kvCacheUsagePercent = stats.kvCacheUsagePercent {
      attributes["llama.kv_cache_usage_percent"] = .double(kvCacheUsagePercent)
    }
    scope.setAttributes(attributes)
  }

  public static func recordLayerMetrics(
    _ metrics: [LayerMetric],
    to scope: Terra.StreamingInferenceScope
  ) {
    for metric in metrics {
      var attributes: [String: AttributeValue] = [
        "llama.layer.name": .string(metric.layerName),
        "llama.layer.duration_ms": .double(metric.durationMS),
      ]
      if let memoryMB = metric.memoryMB {
        attributes["llama.layer.memory_mb"] = .double(memoryMB)
      }
      scope.addEvent("llama.layer.profile", attributes: attributes)
    }
  }
}
