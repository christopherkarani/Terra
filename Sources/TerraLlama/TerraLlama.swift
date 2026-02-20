import Foundation
import OpenTelemetryApi
import TerraCore

public enum TerraLlama {
  public typealias SpanHandle = UInt64

  public enum CallbackStage: Int32, Sendable, CaseIterable {
    case modelLoad = 0
    case promptEval = 1
    case decode = 2
    case streamLifecycle = 3
    case finish = 4
  }

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

  @discardableResult
  public static func withRegisteredScope<R>(
    model: String,
    prompt: String? = nil,
    _ body: @Sendable (SpanHandle, Terra.StreamingInferenceScope) async throws -> R
  ) async rethrows -> R {
    try await traced(model: model, prompt: prompt) { scope in
      let handle = callbackBridge.register(scope: scope)
      defer { callbackBridge.unregister(handle: handle) }
      return try await body(handle, scope)
    }
  }

  public static func registerStreamingScope(_ scope: Terra.StreamingInferenceScope) -> SpanHandle {
    callbackBridge.register(scope: scope)
  }

  public static func unregisterStreamingScope(handle: SpanHandle) {
    callbackBridge.unregister(handle: handle)
  }

  @discardableResult
  public static func recordTokenCallback(
    handle: SpanHandle,
    tokenIndex: Int,
    decodeLatencyMS: Double? = nil,
    logProbability: Double? = nil,
    kvCacheUsagePercent: Double? = nil
  ) -> Bool {
    callbackBridge.withScope(handle: handle) { scope in
      guard tokenIndex >= 0 else { return }
      let emittedAt = monotonicNow()
      let decodedAt: ContinuousClock.Instant? = decodeLatencyMS.flatMap { latency in
        guard latency > 0 else { return nil }
        return emittedAt.advanced(by: .nanoseconds(Int64(latency * 1_000_000)))
      }
      scope.recordTokenLifecycle(
        index: tokenIndex,
        emittedAt: emittedAt,
        decodedAt: decodedAt,
        logProb: logProbability
      )
      scope.recordOutputTokenCount(tokenIndex + 1, at: emittedAt)
      if let kvCacheUsagePercent {
        scope.setAttributes(["llama.kv_cache_usage_percent": .double(kvCacheUsagePercent)])
      }
    }
  }

  @discardableResult
  public static func recordStageCallback(
    handle: SpanHandle,
    stage: CallbackStage,
    tokenCount: Int? = nil,
    durationMS: Double? = nil
  ) -> Bool {
    if stage == .finish {
      return callbackBridge.finish(handle: handle) { scope in
        var attrs: [String: AttributeValue] = [
          Terra.Keys.Terra.stageName: .string("finish")
        ]
        if let tokenCount, tokenCount >= 0 {
          attrs[Terra.Keys.Terra.stageTokenCount] = .int(tokenCount)
          scope.recordOutputTokenCount(tokenCount)
        }
        scope.addEvent(Terra.SpanNames.streamLifecycle, attributes: attrs)
      }
    }

    return callbackBridge.withScope(handle: handle) { scope in
      switch stage {
      case .modelLoad:
        guard let durationMS, durationMS >= 0 else { return }
        scope.setAttributes([Terra.Keys.Terra.latencyModelLoadMs: .double(durationMS)])
        scope.addEvent(
          Terra.SpanNames.modelLoad,
          attributes: [
            Terra.Keys.Terra.stageName: .string("model_load"),
            Terra.Keys.Terra.latencyModelLoadMs: .double(durationMS),
          ]
        )
      case .promptEval:
        guard let durationMS, durationMS >= 0 else { return }
        scope.recordPromptEval(tokens: max(tokenCount ?? 0, 0), durationMs: durationMS)
      case .decode:
        var attrs: [String: AttributeValue] = [
          Terra.Keys.Terra.stageName: .string("decode"),
        ]
        if let durationMS, durationMS >= 0 {
          attrs[Terra.Keys.Terra.latencyDecodeMs] = .double(durationMS)
          scope.setAttributes([Terra.Keys.Terra.latencyDecodeMs: .double(durationMS)])
        }
        if let tokenCount, tokenCount >= 0 {
          attrs[Terra.Keys.Terra.stageTokenCount] = .int(tokenCount)
          scope.recordOutputTokenCount(tokenCount)
        }
        scope.addEvent(Terra.SpanNames.stageDecode, attributes: attrs)
      case .streamLifecycle:
        scope.addEvent(
          Terra.SpanNames.streamLifecycle,
          attributes: [
            Terra.Keys.Terra.stageName: .string(Terra.InferenceStage.streamLifecycle.rawValue)
          ]
        )
      case .finish:
        return
      }
    }
  }

  @discardableResult
  public static func recordStallCallback(
    handle: SpanHandle,
    gapMS: Double,
    thresholdMS: Double,
    baselineP95MS: Double? = nil
  ) -> Bool {
    callbackBridge.withScope(handle: handle) { scope in
      scope.recordStallDetected(gapMs: gapMS, thresholdMs: thresholdMS, baselineP95Ms: baselineP95MS)
    }
  }

  @discardableResult
  public static func finishCallback(handle: SpanHandle) -> Bool {
    callbackBridge.finish(handle: handle) { scope in
      scope.addEvent(
        Terra.SpanNames.streamLifecycle,
        attributes: [Terra.Keys.Terra.stageName: .string("finish")]
      )
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

  private static func monotonicNow() -> ContinuousClock.Instant {
    ContinuousClock().now
  }
}

private final class LlamaCallbackBridge {
  private let lock = NSLock()
  private var nextHandle: TerraLlama.SpanHandle = 1
  private var scopesByHandle: [TerraLlama.SpanHandle: Terra.StreamingInferenceScope] = [:]

  func register(scope: Terra.StreamingInferenceScope) -> TerraLlama.SpanHandle {
    lock.lock()
    defer { lock.unlock() }
    let handle = nextHandle
    nextHandle += 1
    scopesByHandle[handle] = scope
    return handle
  }

  func unregister(handle: TerraLlama.SpanHandle) {
    lock.lock()
    defer { lock.unlock() }
    scopesByHandle.removeValue(forKey: handle)
  }

  @discardableResult
  func withScope(
    handle: TerraLlama.SpanHandle,
    _ body: (Terra.StreamingInferenceScope) -> Void
  ) -> Bool {
    let scope: Terra.StreamingInferenceScope?
    lock.lock()
    scope = scopesByHandle[handle]
    lock.unlock()

    guard let scope else { return false }
    body(scope)
    return true
  }

  @discardableResult
  func finish(
    handle: TerraLlama.SpanHandle,
    _ body: (Terra.StreamingInferenceScope) -> Void
  ) -> Bool {
    let scope: Terra.StreamingInferenceScope?
    lock.lock()
    scope = scopesByHandle.removeValue(forKey: handle)
    lock.unlock()

    guard let scope else { return false }
    body(scope)
    return true
  }
}

private let callbackBridge = LlamaCallbackBridge()

@_cdecl("terra_llama_record_token_event")
public func terra_llama_record_token_event(
  handle: UInt64,
  token_index: UInt64,
  decode_latency_ms: Double,
  log_probability: Double,
  kv_cache_usage_percent: Double
) {
  _ = TerraLlama.recordTokenCallback(
    handle: handle,
    tokenIndex: Int(clamping: token_index),
    decodeLatencyMS: decode_latency_ms >= 0 ? decode_latency_ms : nil,
    logProbability: log_probability.isFinite ? log_probability : nil,
    kvCacheUsagePercent: kv_cache_usage_percent.isFinite ? kv_cache_usage_percent : nil
  )
}

@_cdecl("terra_llama_record_stage_event")
public func terra_llama_record_stage_event(
  handle: UInt64,
  stage: Int32,
  token_count: UInt64,
  duration_ms: Double
) {
  guard let stage = TerraLlama.CallbackStage(rawValue: stage) else { return }
  _ = TerraLlama.recordStageCallback(
    handle: handle,
    stage: stage,
    tokenCount: Int(clamping: token_count),
    durationMS: duration_ms >= 0 ? duration_ms : nil
  )
}

@_cdecl("terra_llama_record_stall_event")
public func terra_llama_record_stall_event(
  handle: UInt64,
  gap_ms: Double,
  threshold_ms: Double,
  baseline_p95_ms: Double
) {
  _ = TerraLlama.recordStallCallback(
    handle: handle,
    gapMS: gap_ms,
    thresholdMS: threshold_ms,
    baselineP95MS: baseline_p95_ms >= 0 ? baseline_p95_ms : nil
  )
}

@_cdecl("terra_llama_finish_stream")
public func terra_llama_finish_stream(handle: UInt64) {
  _ = TerraLlama.finishCallback(handle: handle)
}
