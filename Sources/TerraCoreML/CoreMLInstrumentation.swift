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
  private enum InternalConstants {
    static let synchronousCaptureTimeoutNanoseconds: UInt64 = 2_000_000_000
  }

  private final class AssociatedModelState: NSObject {
    let sourceURL: URL
    let computePlanSummary: TerraCoreMLComputePlanSummary

    init(sourceURL: URL, computePlanSummary: TerraCoreMLComputePlanSummary) {
      self.sourceURL = sourceURL
      self.computePlanSummary = computePlanSummary
    }
  }

  private static var associatedModelStateKey: UInt8 = 0

  /// Configuration for the auto-instrumentation.
  public struct Configuration: Sendable {
    /// Whether CoreML predictions should be traced.
    ///
    /// - Note: When disabled, the swizzle remains installed (if it was ever
    ///   installed) but becomes a fast no-op. This enables deterministic
    ///   `Terra.start()/shutdown()/reconfigure()` lifecycle behavior without
    ///   requiring unswizzling.
    public var enabled: Bool

    /// Model names (as they appear in `gen_ai.request.model`) that should be excluded
    /// from automatic tracing. Useful for low-latency models where tracing overhead is
    /// not desired.
    public var excludedModels: Set<String>

    public init(enabled: Bool = true, excludedModels: Set<String> = []) {
      self.enabled = enabled
      self.excludedModels = excludedModels
    }
  }

  // MARK: - Private state

  private static let lock = NSLock()
  private static var isInstalled = false
  private static var configuration = Configuration()
  package static var computePlanSummaryCapture: @Sendable (URL, MLModelConfiguration) async -> TerraCoreMLComputePlanSummary = {
    url, configuration in
    await MLComputePlanDiagnostics.captureSummary(contentsOf: url, configuration: configuration)
  }
  package static var synchronousCaptureTimeoutNanoseconds = InternalConstants.synchronousCaptureTimeoutNanoseconds

  // MARK: - Public API

  /// Thread-safe check if a model prediction should be traced.
  private static func shouldTrace(_ modelName: String) -> Bool {
    lock.lock()
    let config = configuration
    lock.unlock()

    guard config.enabled else { return false }
    return !config.excludedModels.contains(modelName)
  }

  /// Installs the auto-instrumentation. Safe to call multiple times; only the first call takes effect.
  ///
  /// - Parameter config: Configuration controlling which models are excluded.
  public static func install(_ config: Configuration = .init()) {
    var shouldSwizzle = false

    lock.lock()
    configuration = config
    if !isInstalled, config.enabled {
      isInstalled = true
      shouldSwizzle = true
    }
    lock.unlock()

    guard shouldSwizzle else { return }
    swizzleModelLoad()
    swizzleModelLoadWithConfiguration()
    swizzleAsyncModelLoad()
    swizzlePrediction()
    swizzlePredictionWithOptions()
  }

  // MARK: - Swizzling

  private static func swizzleModelLoad() {
    let selector = NSSelectorFromString("modelWithContentsOfURL:error:")
    guard
      let cls = NSClassFromString("MLModel"),
      let original = class_getClassMethod(cls, selector)
    else { return }

    typealias Impl = @convention(c) (AnyClass, Selector, NSURL, NSErrorPointer) -> MLModel?

    let originalIMP = method_getImplementation(original)
    let originalFn = unsafeBitCast(originalIMP, to: Impl.self)

    let block: @convention(block) (AnyClass, NSURL, NSErrorPointer) -> MLModel? = {
      cls, url, errorPtr in
      let model = originalFn(cls, selector, url, errorPtr)
      if let model {
        associateModel(model, sourceURL: url as URL, configuration: model.configuration)
      }
      return model
    }

    method_setImplementation(original, imp_implementationWithBlock(block))
  }

  private static func swizzleModelLoadWithConfiguration() {
    let selector = NSSelectorFromString("modelWithContentsOfURL:configuration:error:")
    guard
      let cls = NSClassFromString("MLModel"),
      let original = class_getClassMethod(cls, selector)
    else { return }

    typealias Impl = @convention(c) (AnyClass, Selector, NSURL, MLModelConfiguration, NSErrorPointer) -> MLModel?

    let originalIMP = method_getImplementation(original)
    let originalFn = unsafeBitCast(originalIMP, to: Impl.self)

    let block: @convention(block) (AnyClass, NSURL, MLModelConfiguration, NSErrorPointer) -> MLModel? = {
      cls, url, configuration, errorPtr in
      let model = originalFn(cls, selector, url, configuration, errorPtr)
      if let model {
        associateModel(model, sourceURL: url as URL, configuration: configuration)
      }
      return model
    }

    method_setImplementation(original, imp_implementationWithBlock(block))
  }

  private static func swizzleAsyncModelLoad() {
    let selector = NSSelectorFromString("loadContentsOfURL:configuration:completionHandler:")
    guard
      let cls = NSClassFromString("MLModel"),
      let original = class_getClassMethod(cls, selector)
    else { return }

    typealias Completion = @convention(block) (MLModel?, NSError?) -> Void
    typealias Impl = @convention(c) (AnyClass, Selector, NSURL, MLModelConfiguration, @escaping Completion) -> Void

    let originalIMP = method_getImplementation(original)
    let originalFn = unsafeBitCast(originalIMP, to: Impl.self)

    let block: @convention(block) (AnyClass, NSURL, MLModelConfiguration, @escaping Completion) -> Void = {
      cls, url, configuration, completion in
      let wrappedCompletion: Completion = { model, error in
        if let model {
          associateModel(model, sourceURL: url as URL, configuration: configuration)
        }
        completion(model, error)
      }
      originalFn(cls, selector, url, configuration, wrappedCompletion)
    }

    method_setImplementation(original, imp_implementationWithBlock(block))
  }

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

      guard CoreMLInstrumentation.shouldTrace(modelName) else {
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
      let startedAt = ContinuousClock.now
      let startMemory = TerraSystemProfiler.isInstalled
        ? TerraSystemProfiler.captureMemorySnapshot()
        : nil
      OpenTelemetry.instance.contextProvider.setActiveSpan(span)

      let result = originalFn(self_, selector, features, errorPtr)
      let durationMS = CoreMLInstrumentation.elapsedMs(since: startedAt)
      span.setAttribute(key: "terra.coreml.prediction.duration_ms", value: .double(durationMS))
      if TerraMetalProfiler.isInstalled, CoreMLInstrumentation.modelLikelyUsesGPU(model) {
        span.setAttributes(TerraMetalProfiler.attributes(computeTimeMS: durationMS))
      }
      CoreMLInstrumentation.attachAssociatedDiagnostics(to: span, model: model)
      let endMemory = TerraSystemProfiler.isInstalled
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

      guard CoreMLInstrumentation.shouldTrace(modelName) else {
        return originalFn(self_, selector, features, options, errorPtr)
      }

      // See note in `swizzlePrediction`: dedup is context-based, not atomic by design.
      guard OpenTelemetry.instance.contextProvider.activeSpan == nil else {
        return originalFn(self_, selector, features, options, errorPtr)
      }

      let span = CoreMLInstrumentation.buildSpan(modelName: modelName, model: model)
      let startedAt = ContinuousClock.now
      let startMemory = TerraSystemProfiler.isInstalled
        ? TerraSystemProfiler.captureMemorySnapshot()
        : nil
      OpenTelemetry.instance.contextProvider.setActiveSpan(span)

      let result = originalFn(self_, selector, features, options, errorPtr)
      let durationMS = CoreMLInstrumentation.elapsedMs(since: startedAt)
      span.setAttribute(key: "terra.coreml.prediction.duration_ms", value: .double(durationMS))
      if TerraMetalProfiler.isInstalled, CoreMLInstrumentation.modelLikelyUsesGPU(model) {
        span.setAttributes(TerraMetalProfiler.attributes(computeTimeMS: durationMS))
      }
      CoreMLInstrumentation.attachAssociatedDiagnostics(to: span, model: model)
      let endMemory = TerraSystemProfiler.isInstalled
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
      .spanBuilder(spanName: "gen_ai.inference")
      .setSpanKind(spanKind: .internal)
      .setAttribute(key: Terra.Keys.GenAI.operationName, value: "inference")
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

  private static func elapsedMs(since start: ContinuousClock.Instant) -> Double {
    let elapsed = ContinuousClock.now - start
    return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
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

  private static func associateModel(
    _ model: MLModel,
    sourceURL: URL,
    configuration: MLModelConfiguration
  ) {
    let summary = captureSummarySynchronously(contentsOf: sourceURL, configuration: configuration)
    let state = AssociatedModelState(sourceURL: sourceURL, computePlanSummary: summary)
    objc_setAssociatedObject(
      model,
      &associatedModelStateKey,
      state,
      .OBJC_ASSOCIATION_RETAIN_NONATOMIC
    )
  }

  private static func attachAssociatedDiagnostics(to span: any Span, model: MLModel) {
    guard
      let state = objc_getAssociatedObject(model, &associatedModelStateKey) as? AssociatedModelState
    else {
      return
    }

    let summary = state.computePlanSummary
    span.setAttributes(summary.telemetryAttributes)
    span.setAttributes(ComputePlanAnalysis.analyze(summary).telemetryAttributes)
  }

  package static func captureSummarySynchronously(
    contentsOf url: URL,
    configuration: MLModelConfiguration
  ) -> TerraCoreMLComputePlanSummary {
    let semaphore = DispatchSemaphore(value: 0)
    let summaryBox = LockedSummaryBox()

    Task.detached(priority: .utility) {
      let captured = await computePlanSummaryCapture(url, configuration)
      summaryBox.store(captured)
      semaphore.signal()
    }

    let waitResult = semaphore.wait(
      timeout: .now() + .nanoseconds(Int(synchronousCaptureTimeoutNanoseconds))
    )
    guard waitResult == .success, let summary = summaryBox.load() else {
      return makeTimedOutSummary()
    }
    return summary
  }

  package static func resetTestingHooks() {
    computePlanSummaryCapture = { url, configuration in
      await MLComputePlanDiagnostics.captureSummary(contentsOf: url, configuration: configuration)
    }
    synchronousCaptureTimeoutNanoseconds = InternalConstants.synchronousCaptureTimeoutNanoseconds
  }

  private static func makeTimedOutSummary() -> TerraCoreMLComputePlanSummary {
    TerraCoreMLComputePlanSummary(
      captureStatus: .loadFailed,
      modelStructure: "unsupported",
      estimatedPrimaryDevice: "unknown",
      supportedDevices: [],
      nodeCount: 0,
      captureDurationMS: 0,
      operationEstimates: [],
      errorType: "terra.coreml.compute_plan.capture_timeout",
      probeStatus: TerraCoreMLComputePlanSummary.CaptureStatus.loadFailed.rawValue,
      probeSource: "mlcomputeplan"
    )
  }

  private final class LockedSummaryBox: @unchecked Sendable {
    private let lock = NSLock()
    private var summary: TerraCoreMLComputePlanSummary?

    func store(_ summary: TerraCoreMLComputePlanSummary) {
      lock.lock()
      self.summary = summary
      lock.unlock()
    }

    func load() -> TerraCoreMLComputePlanSummary? {
      lock.lock()
      let summary = self.summary
      lock.unlock()
      return summary
    }
  }
}
#endif
