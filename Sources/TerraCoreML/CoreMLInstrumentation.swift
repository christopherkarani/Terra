#if canImport(CoreML)
import CoreML
import Foundation
import ObjectiveC
import OpenTelemetryApi
import OpenTelemetrySdk
import TerraCore
import TerraMetalProfiler
import TerraSystemProfiler

/// Installs ObjC method swizzling on `MLModel` to automatically create Terra inference spans
/// for every Core ML prediction without requiring manual instrumentation.
///
/// Call `CoreMLInstrumentation.install()` once at app startup (e.g., in `applicationDidFinishLaunching`).
/// Spans created by swizzling include `terra.auto_instrumented = true` and will be skipped if
/// a Terra span is already active (dedup guard).
public enum CoreMLInstrumentation {

  /// Configuration for the auto-instrumentation.
  public struct Configuration: Sendable {
    /// Model names (as they appear in `gen_ai.request.model`) that should be excluded
    /// from automatic tracing. Useful for low-latency models where tracing overhead is
    /// not desired.
    public var excludedModels: Set<String>

    public init(excludedModels: Set<String> = []) {
      self.excludedModels = excludedModels
    }
  }

  // MARK: - Private state

  private static let lock = NSLock()
  private static var isInstalled = false
  private static var configuration = Configuration()

  // MARK: - Public API

  /// Installs the auto-instrumentation. Safe to call multiple times; only the first call takes effect.
  ///
  /// - Parameter config: Configuration controlling which models are excluded.
  public static func install(_ config: Configuration = .init()) {
    lock.lock()
    defer { lock.unlock() }

    guard !isInstalled else { return }
    isInstalled = true
    configuration = config

    swizzlePrediction()
    swizzlePredictionWithOptions()
  }

  // MARK: - Swizzling

  private static func swizzlePrediction() {
    // ObjC selector: -[MLModel predictionFromFeatures:error:]
    let selector = NSSelectorFromString("predictionFromFeatures:error:")
    guard
      let cls = NSClassFromString("MLModel"),
      let original = class_getInstanceMethod(cls, selector)
    else { return }

    typealias Impl = @convention(c) (AnyObject, Selector, MLFeatureProvider, NSErrorPointer) -> MLFeatureProvider?

    let originalIMP = method_getImplementation(original)
    let originalFn = unsafeBitCast(originalIMP, to: Impl.self)

    let block: @convention(block) (AnyObject, MLFeatureProvider, NSErrorPointer) -> MLFeatureProvider? = {
      (self_, features, errorPtr) in
      guard let model = self_ as? MLModel else {
        return originalFn(self_, selector, features, errorPtr)
      }

      let modelName = CoreMLInstrumentation.resolveModelName(model)

      guard !CoreMLInstrumentation.configuration.excludedModels.contains(modelName) else {
        return originalFn(self_, selector, features, errorPtr)
      }

      // Known limitation: this dedup guard is context-based and intentionally non-atomic.
      // In rare highly-concurrent call patterns two threads can both observe no active span,
      // producing duplicate telemetry. We keep this lock-free to avoid adding synchronization
      // overhead in the hot prediction path unless real-world evidence justifies it.
      guard OpenTelemetry.instance.contextProvider.activeSpan == nil else {
        return originalFn(self_, selector, features, errorPtr)
      }

      let span = CoreMLInstrumentation.buildSpan(modelName: modelName, model: model)
      let startedAt = Date()
      let startMemory = TerraSystemProfiler.isMemoryProfilerEnabled
        ? TerraSystemProfiler.captureMemorySnapshot()
        : nil
      OpenTelemetry.instance.contextProvider.setActiveSpan(span)

      let result = originalFn(self_, selector, features, errorPtr)
      let durationMS = Date().timeIntervalSince(startedAt) * 1000
      span.setAttribute(key: "terra.coreml.prediction.duration_ms", value: .double(durationMS))
      if TerraMetalProfiler.isInstalled, CoreMLInstrumentation.modelLikelyUsesGPU(model) {
        span.setAttributes(TerraMetalProfiler.attributes(computeTimeMS: durationMS))
      }
      let endMemory = TerraSystemProfiler.isMemoryProfilerEnabled
        ? TerraSystemProfiler.captureMemorySnapshot()
        : nil
      span.setAttributes(TerraSystemProfiler.memoryDeltaAttributes(start: startMemory, end: endMemory))

      if result == nil, let errorPtr = errorPtr, let error = errorPtr.pointee {
        span.status = .error(description: error.localizedDescription)
      }

      span.end()
      OpenTelemetry.instance.contextProvider.removeContextForSpan(span)
      return result
    }

    method_setImplementation(original, imp_implementationWithBlock(block))
  }

  private static func swizzlePredictionWithOptions() {
    // ObjC selector: -[MLModel predictionFromFeatures:options:error:]
    let selector = NSSelectorFromString("predictionFromFeatures:options:error:")
    guard
      let cls = NSClassFromString("MLModel"),
      let original = class_getInstanceMethod(cls, selector)
    else { return }

    typealias Impl = @convention(c) (AnyObject, Selector, MLFeatureProvider, MLPredictionOptions, NSErrorPointer) -> MLFeatureProvider?

    let originalIMP = method_getImplementation(original)
    let originalFn = unsafeBitCast(originalIMP, to: Impl.self)

    let block: @convention(block) (AnyObject, MLFeatureProvider, MLPredictionOptions, NSErrorPointer) -> MLFeatureProvider? = {
      (self_, features, options, errorPtr) in
      guard let model = self_ as? MLModel else {
        return originalFn(self_, selector, features, options, errorPtr)
      }

      let modelName = CoreMLInstrumentation.resolveModelName(model)

      guard !CoreMLInstrumentation.configuration.excludedModels.contains(modelName) else {
        return originalFn(self_, selector, features, options, errorPtr)
      }

      // See note in `swizzlePrediction`: dedup is context-based, not atomic by design.
      guard OpenTelemetry.instance.contextProvider.activeSpan == nil else {
        return originalFn(self_, selector, features, options, errorPtr)
      }

      let span = CoreMLInstrumentation.buildSpan(modelName: modelName, model: model)
      let startedAt = Date()
      let startMemory = TerraSystemProfiler.isMemoryProfilerEnabled
        ? TerraSystemProfiler.captureMemorySnapshot()
        : nil
      OpenTelemetry.instance.contextProvider.setActiveSpan(span)

      let result = originalFn(self_, selector, features, options, errorPtr)
      let durationMS = Date().timeIntervalSince(startedAt) * 1000
      span.setAttribute(key: "terra.coreml.prediction.duration_ms", value: .double(durationMS))
      if TerraMetalProfiler.isInstalled, CoreMLInstrumentation.modelLikelyUsesGPU(model) {
        span.setAttributes(TerraMetalProfiler.attributes(computeTimeMS: durationMS))
      }
      let endMemory = TerraSystemProfiler.isMemoryProfilerEnabled
        ? TerraSystemProfiler.captureMemorySnapshot()
        : nil
      span.setAttributes(TerraSystemProfiler.memoryDeltaAttributes(start: startMemory, end: endMemory))

      if result == nil, let errorPtr = errorPtr, let error = errorPtr.pointee {
        span.status = .error(description: error.localizedDescription)
      }

      span.end()
      OpenTelemetry.instance.contextProvider.removeContextForSpan(span)
      return result
    }

    method_setImplementation(original, imp_implementationWithBlock(block))
  }

  // MARK: - Span construction

  internal static func buildSpan(modelName: String, model: MLModel) -> Span {
    let computeUnitsLabel = model.configuration.computeUnits.terraLabel
    return OpenTelemetry.instance.tracerProvider
      .get(instrumentationName: Terra.instrumentationName)
      .spanBuilder(spanName: "inference \(modelName)")
      .setSpanKind(spanKind: .internal)
      .setAttribute(key: Terra.Keys.GenAI.operationName, value: Terra.OperationName.inference.rawValue)
      .setAttribute(key: Terra.Keys.GenAI.requestModel, value: modelName)
      .setAttribute(key: Terra.Keys.GenAI.providerName, value: "on_device")
      .setAttribute(key: Terra.Keys.Terra.runtime, value: "coreml")
      .setAttribute(key: Terra.Keys.Terra.autoInstrumented, value: true)
      .setAttribute(key: TerraCoreML.Keys.computeUnits, value: computeUnitsLabel)
      .startSpan()
  }

  // MARK: - Model name resolution

  internal static func resolveModelName(_ model: MLModel) -> String {
    // 1. Creator-defined metadata key (most explicit)
    if let name = model.modelDescription.metadata[MLModelMetadataKey.creatorDefinedKey] as? String,
      let sanitized = sanitizeModelName(name)
    {
      return sanitized
    }

    // 2. modelDisplayName (available macOS 13 / iOS 16+)
    if #available(macOS 13, iOS 16, tvOS 16, watchOS 9, *) {
      if let name = model.configuration.modelDisplayName,
         let sanitized = sanitizeModelName(name)
      {
        return sanitized
      }
    }

    // 3. Final fallback
    return "unknown_coreml_model"
  }

  internal static func sanitizeModelName(_ raw: String) -> String? {
    let filtered = String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !filtered.isEmpty else { return nil }
    if filtered.count <= 256 {
      return filtered
    }
    return String(filtered.prefix(256))
  }

  private static func modelLikelyUsesGPU(_ model: MLModel) -> Bool {
    switch model.configuration.computeUnits {
    case .all, .cpuAndGPU:
      return true
    case .cpuOnly, .cpuAndNeuralEngine:
      return false
    @unknown default:
      return false
    }
  }
}
#endif
