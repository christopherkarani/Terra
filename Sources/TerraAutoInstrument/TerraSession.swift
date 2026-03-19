import Foundation
import OpenTelemetryApi
import TerraCoreML
import TerraSystemProfiler

#if canImport(CoreML)
import CoreML
#endif

#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#endif

#if canImport(Darwin)
import Darwin
#endif

#if canImport(UIKit)
import UIKit
#endif

package protocol TerraDashboardDiscovering: Sendable {
  func discoverEndpoint(timeout: Duration) async -> URL?
}

package protocol TerraSessionLogging: Sendable {
  func warning(_ message: String)
  func error(_ message: String)
}

package struct TerraSessionDependencies: @unchecked Sendable {
  package var dashboardDiscovery: any TerraDashboardDiscovering
  package var logger: any TerraSessionLogging
  package var isSimulator: Bool
  package var currentThermalState: @Sendable () -> ProcessInfo.ThermalState
  package var memoryFootprint: @Sendable () -> UInt64?
  package var currentDate: @Sendable () -> Date
  package var startRuntime: @Sendable (Terra.Configuration) async throws -> Void
  package var isRuntimeRunning: @Sendable () -> Bool
  #if canImport(CoreML)
  package var computePlanSummary: @Sendable (URL, MLModelConfiguration) async -> TerraCoreMLComputePlanSummary
  #endif

  #if canImport(CoreML)
  package init(
    dashboardDiscovery: any TerraDashboardDiscovering = BonjourTerraDashboardDiscovery(),
    logger: any TerraSessionLogging = TerraSessionOSLogger(),
    isSimulator: Bool = TerraSessionDefaults.isSimulator,
    currentThermalState: @escaping @Sendable () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState },
    memoryFootprint: @escaping @Sendable () -> UInt64? = { TerraSessionDefaults.capturePhysFootprintBytes() },
    currentDate: @escaping @Sendable () -> Date = { Date() },
    startRuntime: @escaping @Sendable (Terra.Configuration) async throws -> Void = { try await Terra.start($0) },
    isRuntimeRunning: @escaping @Sendable () -> Bool = { Terra.isRunning },
    computePlanSummary: @escaping @Sendable (URL, MLModelConfiguration) async -> TerraCoreMLComputePlanSummary = { url, configuration in
      await MLComputePlanDiagnostics.captureSummary(contentsOf: url, configuration: configuration)
    }
  ) {
    self.dashboardDiscovery = dashboardDiscovery
    self.logger = logger
    self.isSimulator = isSimulator
    self.currentThermalState = currentThermalState
    self.memoryFootprint = memoryFootprint
    self.currentDate = currentDate
    self.startRuntime = startRuntime
    self.isRuntimeRunning = isRuntimeRunning
    self.computePlanSummary = computePlanSummary
  }
  #else
  package init(
    dashboardDiscovery: any TerraDashboardDiscovering = BonjourTerraDashboardDiscovery(),
    logger: any TerraSessionLogging = TerraSessionOSLogger(),
    isSimulator: Bool = TerraSessionDefaults.isSimulator,
    currentThermalState: @escaping @Sendable () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState },
    memoryFootprint: @escaping @Sendable () -> UInt64? = { TerraSessionDefaults.capturePhysFootprintBytes() },
    currentDate: @escaping @Sendable () -> Date = { Date() },
    startRuntime: @escaping @Sendable (Terra.Configuration) async throws -> Void = { try await Terra.start($0) },
    isRuntimeRunning: @escaping @Sendable () -> Bool = { Terra.isRunning }
  ) {
    self.dashboardDiscovery = dashboardDiscovery
    self.logger = logger
    self.isSimulator = isSimulator
    self.currentThermalState = currentThermalState
    self.memoryFootprint = memoryFootprint
    self.currentDate = currentDate
    self.startRuntime = startRuntime
    self.isRuntimeRunning = isRuntimeRunning
  }
  #endif
}

package actor TerraSession {
  package struct Configuration: Sendable, Equatable {
    package var dashboardEndpoint: URL?
    package var dashboardDiscoveryTimeout: TimeInterval
    package var memorySamplingInterval: TimeInterval?
    package var exportSimulatorMetrics: Bool
    package var autoStartRuntime: Bool
    package var modelLoadCacheURL: URL

    package init(
      dashboardEndpoint: URL? = nil,
      dashboardDiscoveryTimeout: TimeInterval = 2,
      memorySamplingInterval: TimeInterval? = 1,
      exportSimulatorMetrics: Bool = false
    ) {
      self.dashboardEndpoint = dashboardEndpoint
      self.dashboardDiscoveryTimeout = dashboardDiscoveryTimeout
      self.memorySamplingInterval = memorySamplingInterval
      self.exportSimulatorMetrics = exportSimulatorMetrics
      self.autoStartRuntime = true
      self.modelLoadCacheURL = TerraSessionDefaults.defaultModelLoadCacheURL()
    }
  }

  package enum MemorySampleReason: String, Sendable {
    case timer
    case warning
  }

  package struct FeatureSummary: Codable, Hashable, Sendable {
    package let name: String
    package let kind: String
    package let shape: [Int]?

    package init(name: String, kind: String, shape: [Int]? = nil) {
      self.name = name
      self.kind = kind
      self.shape = shape
    }
  }

  private let configuration: Configuration
  private let dependencies: TerraSessionDependencies
  private let notificationCenter: NotificationCenter

  private let sessionID = UUID().uuidString
  private var rootSpan: (any Span)?
  private var isStarted = false
  private var thermalStateLabel = "unknown"
  private var thermalObserver: NSObjectProtocol?
  private var memoryWarningObserver: NSObjectProtocol?
  private var memorySamplingTask: Task<Void, Never>?
  private static let modelLoadCacheStore = TerraSessionModelLoadCacheStore()

  package init(configuration: Configuration = .init()) {
    self.configuration = configuration
    self.dependencies = .init()
    self.notificationCenter = .default
  }

  package init(
    configuration: Configuration = .init(),
    dependencies: TerraSessionDependencies,
    notificationCenter: NotificationCenter = .default
  ) {
    self.configuration = configuration
    self.dependencies = dependencies
    self.notificationCenter = notificationCenter
  }

  package func start() async throws {
    guard !isStarted else { return }

    if keepsSessionSignalsLocal {
      dependencies.logger.warning("Simulator export disabled. TerraSession will capture simulator spans locally but will not export them.")
    }

    if configuration.autoStartRuntime, !dependencies.isRuntimeRunning() {
      var runtimeConfig = Terra.Configuration()
      runtimeConfig.features = Terra._minimalFeatures()
      if let endpoint = await resolveExporterEndpoint() {
        runtimeConfig.destination = .endpoint(endpoint)
      }
      try await dependencies.startRuntime(runtimeConfig)
    }

    thermalStateLabel = TerraSessionDefaults.thermalStateLabel(dependencies.currentThermalState())
    let keepsSessionSignalsLocal = self.keepsSessionSignalsLocal
    let span = TerraSessionDefaults.makeSpan(named: Terra.SpanNames.session)
    span.setAttributes(TerraSessionDefaults.sessionSignalAttributes([
      "terra.session.id": .string(sessionID),
      "terra.session.start_time_unix_ms": .int(Int(dependencies.currentDate().timeIntervalSince1970 * 1000)),
      "terra.session.device_model": .string(TerraSessionDefaults.deviceModel()),
      "terra.session.os_version": .string(TerraSessionDefaults.osVersion()),
      "terra.device.is_simulator": .bool(dependencies.isSimulator),
      Terra.Keys.Terra.thermalState: .string(thermalStateLabel),
      Terra.Keys.Terra.runtime: .string("coreml"),
    ], localOnly: keepsSessionSignalsLocal))

    rootSpan = span
    isStarted = true

    if dependencies.isSimulator {
      dependencies.logger.warning("Simulator detected. Terra will label the session as simulator data.")
      let warningAttributes: [String: AttributeValue] = [
        "terra.warning.code": .string("simulator"),
        "terra.warning.message": .string("Simulator metrics are not representative of on-device performance."),
      ]
      span.addEvent(
        name: "terra.warning",
        attributes: warningAttributes,
        timestamp: dependencies.currentDate()
      )
    }

    installThermalObservation()
    installMemoryWarningObservation()
    startMemorySamplingIfNeeded()
  }

  package func end() async {
    guard isStarted else { return }
    isStarted = false
    memorySamplingTask?.cancel()
    memorySamplingTask = nil
    if let thermalObserver {
      notificationCenter.removeObserver(thermalObserver)
      self.thermalObserver = nil
    }
    if let memoryWarningObserver {
      notificationCenter.removeObserver(memoryWarningObserver)
      self.memoryWarningObserver = nil
    }
    rootSpan?.end()
    rootSpan = nil
  }

  package func resolveExporterEndpoint() async -> URL? {
    if let dashboardEndpoint = configuration.dashboardEndpoint {
      return dashboardEndpoint
    }
    if let discovered = await dependencies.dashboardDiscovery.discoverEndpoint(
      timeout: .milliseconds(Int64(configuration.dashboardDiscoveryTimeout * 1000))
    ) {
      return discovered
    }
    return URL(string: "http://127.0.0.1:4318")
  }

  package func recordThermalTransition(to state: ProcessInfo.ThermalState) {
    let label = TerraSessionDefaults.thermalStateLabel(state)
    thermalStateLabel = label
    rootSpan?.addEvent(
      name: "terra.thermal.transition",
      attributes: [
        Terra.Keys.Terra.thermalState: .string(label),
        "terra.session.id": .string(sessionID),
      ],
      timestamp: dependencies.currentDate()
    )
  }

  package func recordMemorySample(reason: MemorySampleReason) {
    guard let bytes = dependencies.memoryFootprint() else {
      dependencies.logger.error("Failed to capture phys_footprint for TerraSession memory sample.")
      return
    }
    rootSpan?.addEvent(
      name: "terra.memory.sample",
      attributes: [
        "terra.memory.sample_reason": .string(reason.rawValue),
        "terra.memory.phys_footprint_bytes": .int(Int(bytes)),
        Terra.Keys.Terra.thermalState: .string(thermalStateLabel),
      ],
      timestamp: dependencies.currentDate()
    )
  }

  package func recordMemoryWarning() {
    guard let bytes = dependencies.memoryFootprint() else {
      dependencies.logger.error("Failed to capture phys_footprint for TerraSession memory warning.")
      return
    }
    rootSpan?.addEvent(
      name: "terra.memory.warning",
      attributes: [
        "terra.memory.phys_footprint_bytes": .int(Int(bytes)),
        Terra.Keys.Terra.thermalState: .string(thermalStateLabel),
      ],
      timestamp: dependencies.currentDate()
    )
  }

  #if canImport(CoreML)
  /// Actor-isolated model load API. Always `await` this call from outside the session actor.
  package func loadModel(
    contentsOf url: URL,
    configuration: MLModelConfiguration = MLModelConfiguration()
  ) async throws -> MLModel {
    try await recordModelLoad(contentsOf: url, configuration: configuration, modelName: TerraSessionDefaults.modelName(for: url)) {
      if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
        return try await MLModel.load(contentsOf: url, configuration: configuration)
      }
      return try MLModel(contentsOf: url, configuration: configuration)
    }
  }

  /// Actor-isolated prediction API. Always `await` this call from outside the session actor.
  package func predict(
    _ model: MLModel,
    from input: any MLFeatureProvider,
    options: MLPredictionOptions = .init()
  ) async throws -> any MLFeatureProvider {
    let summaries = TerraSessionDefaults.featureSummaries(from: input)
    return try await recordInference(
      modelName: TerraSessionDefaults.modelName(for: model),
      featureSummaries: summaries,
      computeUnits: model.configuration.computeUnits
    ) {
      try await model.prediction(from: input, options: options)
    }
  }

  package func recordModelLoad<R>(
    contentsOf url: URL,
    configuration: MLModelConfiguration,
    modelName: String,
    _ load: @escaping @Sendable () async throws -> R
  ) async throws -> R {
    let cacheKey = modelLoadCacheKey(for: url, configuration: configuration)
    let cacheURL = self.configuration.modelLoadCacheURL
    let isCold = await Self.modelLoadCacheStore.isCold(cacheKey: cacheKey, fileURL: cacheURL)
    let thermalStateLabel = self.thermalStateLabel
    let keepsSessionSignalsLocal = self.keepsSessionSignalsLocal
    let startedAt = TerraSessionDefaults.monotonicTime()
    let computePlanSummary = await dependencies.computePlanSummary(url, configuration)

    return try await withSessionContext { [self, cacheKey, cacheURL, computePlanSummary, isCold, thermalStateLabel, keepsSessionSignalsLocal] in
      let span = TerraSessionDefaults.makeSpan(named: Terra.SpanNames.modelLoad)
      span.setAttributes(TerraSessionDefaults.sessionSignalAttributes([
        Terra.Keys.GenAI.requestModel: .string(modelName),
        Terra.Keys.Terra.runtime: .string("coreml"),
        Terra.Keys.Terra.thermalState: .string(thermalStateLabel),
        "terra.coreml.compute_units": .string(TerraSessionDefaults.computeUnitsLabel(configuration.computeUnits)),
        "terra.coreml.load.is_cold": .bool(isCold),
        "terra.coreml.load.cache_key": .string(cacheKey),
      ], localOnly: keepsSessionSignalsLocal))
      span.setAttributes(
        TerraCoreML.routeEvidence(
          computeUnits: configuration.computeUnits,
          captureMode: .heuristic,
          confidence: .low
        ).attributes
      )
      span.setAttributes(computePlanSummary.telemetryAttributes)

      return try await OpenTelemetry.instance.contextProvider.withActiveSpan(span) {
        do {
          let model = try await load()
          let durationMS = TerraSessionDefaults.elapsedMilliseconds(since: startedAt)
          span.setAttribute(key: "terra.coreml.load.duration_ms", value: .double(durationMS))
          span.setAttribute(key: Terra.Keys.Terra.latencyModelLoadMs, value: .double(durationMS))
          do {
            try await Self.modelLoadCacheStore.markWarm(
              cacheKey: cacheKey,
              fileURL: cacheURL
            )
          } catch {
            self.dependencies.logger.error("Failed to persist Terra model-load cache.")
          }
          span.end()
          return model
        } catch {
          TerraSessionDefaults.recordCoreMLError(on: span, error: error, at: self.dependencies.currentDate())
          span.end()
          throw error
        }
      }
    }
  }

  package func recordInference<R>(
    modelName: String,
    featureSummaries: [FeatureSummary],
    computeUnits: MLComputeUnits? = nil,
    _ body: @escaping @Sendable () async throws -> R
  ) async throws -> R {
    let thermalStateLabel = self.thermalStateLabel
    let keepsSessionSignalsLocal = self.keepsSessionSignalsLocal
    return try await withSessionContext { [self, thermalStateLabel, keepsSessionSignalsLocal] in
      let span = TerraSessionDefaults.makeSpan(named: Terra.SpanNames.inference)
      var attributes = TerraSessionDefaults.sessionSignalAttributes([
        Terra.Keys.GenAI.operationName: .string("inference"),
        Terra.Keys.GenAI.requestModel: .string(modelName),
        Terra.Keys.Terra.runtime: .string("coreml"),
        Terra.Keys.Terra.thermalState: .string(thermalStateLabel),
        "terra.coreml.input_summary": .string(TerraSessionDefaults.serializedFeatureSummary(featureSummaries)),
      ], localOnly: keepsSessionSignalsLocal)
      if let computeUnits {
        attributes["terra.coreml.compute_units"] = .string(TerraSessionDefaults.computeUnitsLabel(computeUnits))
        attributes.merge(
          TerraCoreML.routeEvidence(
            computeUnits: computeUnits,
            captureMode: .heuristic,
            confidence: .low
          ).attributes
        ) { _, newValue in newValue }
      }
      span.setAttributes(attributes)

      return try await OpenTelemetry.instance.contextProvider.withActiveSpan(span) {
        let startedAt = TerraSessionDefaults.monotonicTime()
        do {
          let result = try await body()
          let durationMS = TerraSessionDefaults.elapsedMilliseconds(since: startedAt)
          span.setAttribute(key: "terra.coreml.prediction.duration_ms", value: .double(durationMS))
          span.setAttribute(key: Terra.Keys.Terra.latencyE2EMs, value: .double(durationMS))
          span.setAttributes(NeuralEngineResearch.coreMLAttributes())
          span.end()
          return result
        } catch {
          let durationMS = TerraSessionDefaults.elapsedMilliseconds(since: startedAt)
          span.setAttribute(key: "terra.coreml.prediction.duration_ms", value: .double(durationMS))
          span.setAttribute(key: Terra.Keys.Terra.latencyE2EMs, value: .double(durationMS))
          span.setAttributes(NeuralEngineResearch.coreMLAttributes())
          TerraSessionDefaults.recordCoreMLError(on: span, error: error, at: self.dependencies.currentDate())
          span.end()
          throw error
        }
      }
    }
  }
  #endif

  private func installThermalObservation() {
    thermalObserver = notificationCenter.addObserver(
      forName: ProcessInfo.thermalStateDidChangeNotification,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      guard let self else { return }
      Task { await self.recordThermalTransition(to: self.dependencies.currentThermalState()) }
    }
  }

  private func installMemoryWarningObservation() {
    #if canImport(UIKit)
    memoryWarningObserver = notificationCenter.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      guard let self else { return }
      Task { await self.recordMemoryWarning() }
    }
    #endif
  }

  private func startMemorySamplingIfNeeded() {
    guard let interval = configuration.memorySamplingInterval, interval > 0 else { return }
    memorySamplingTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        if Task.isCancelled { break }
        await self.recordMemorySample(reason: .timer)
      }
    }
  }

  private func withSessionContext<R>(
    _ operation: @escaping @Sendable () async throws -> R
  ) async throws -> R {
    guard let rootSpan else { return try await operation() }
    return try await OpenTelemetry.instance.contextProvider.withActiveSpan(rootSpan) {
      try await operation()
    }
  }

  private var keepsSessionSignalsLocal: Bool {
    dependencies.isSimulator && !configuration.exportSimulatorMetrics
  }

  #if canImport(CoreML)
  private func modelLoadCacheKey(for url: URL, configuration: MLModelConfiguration) -> String {
    let path = url.standardizedFileURL.path
    let modificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
      ?? .distantPast
    let configurationFingerprint = TerraSessionDefaults.modelLoadConfigurationFingerprint(configuration)
    let raw = "\(path)|\(modificationDate.timeIntervalSince1970)|\(configurationFingerprint)"
    return TerraSessionDefaults.sha256(raw)
  }
  #endif
}

package actor TerraSessionModelLoadCacheStore {
  private struct CacheState {
    var isLoaded = false
    var keys: Set<String> = []
  }

  private var states: [URL: CacheState] = [:]

  package func isCold(cacheKey: String, fileURL: URL) -> Bool {
    loadIfNeeded(fileURL: fileURL)
    return !(states[fileURL]?.keys.contains(cacheKey) ?? false)
  }

  package func markWarm(cacheKey: String, fileURL: URL) throws {
    loadIfNeeded(fileURL: fileURL)
    var state = states[fileURL] ?? CacheState()
    state.keys.insert(cacheKey)
    try persist(state, fileURL: fileURL)
    states[fileURL] = state
  }

  private func loadIfNeeded(fileURL: URL) {
    if states[fileURL]?.isLoaded == true {
      return
    }

    do {
      let data = try Data(contentsOf: fileURL)
      let keys = try JSONDecoder().decode(Set<String>.self, from: data)
      states[fileURL] = CacheState(isLoaded: true, keys: keys)
    } catch {
      states[fileURL] = CacheState(isLoaded: true, keys: [])
    }
  }

  private func persist(_ state: CacheState, fileURL: URL) throws {
    let data = try JSONEncoder().encode(state.keys)
    let directoryURL = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try data.write(to: fileURL, options: .atomic)
  }
}

private enum TerraSessionDefaults {
  static var isSimulator: Bool {
    #if targetEnvironment(simulator)
    return true
    #else
    return false
    #endif
  }

  static func defaultModelLoadCacheURL() -> URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base
      .appendingPathComponent("terra", isDirectory: true)
      .appendingPathComponent("model-load-cache.json", isDirectory: false)
  }

  static func makeSpan(named name: String) -> any Span {
    let tracer = OpenTelemetry.instance.tracerProvider.get(instrumentationName: Terra.instrumentationName)
    return tracer.spanBuilder(spanName: name)
      .setSpanKind(spanKind: .internal)
      .startSpan()
  }

  static func deviceModel() -> String {
    #if canImport(Darwin)
    var size: size_t = 0
    sysctlbyname("hw.machine", nil, &size, nil, 0)
    var machine = [CChar](repeating: 0, count: Int(size))
    sysctlbyname("hw.machine", &machine, &size, nil, 0)
    return String(cString: machine)
    #else
    return "unknown"
    #endif
  }

  static func osVersion() -> String {
    #if canImport(UIKit)
    return UIDevice.current.systemVersion
    #elseif os(macOS)
    return ProcessInfo.processInfo.operatingSystemVersionString
    #else
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    #endif
  }

  static func modelName(for url: URL) -> String {
    let candidate = url.deletingPathExtension().lastPathComponent
    return candidate.isEmpty ? "coreml-model" : candidate
  }

  #if canImport(CoreML)
  static func modelName(for model: MLModel) -> String {
    if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *),
       let name = model.configuration.modelDisplayName,
       !name.isEmpty
    {
      return name
    }
    return "coreml-model"
  }

  static func modelLoadConfigurationFingerprint(_ configuration: MLModelConfiguration) -> String {
    var components = [
      "compute_units=\(computeUnitsLabel(configuration.computeUnits))",
      "low_precision_gpu=\(configuration.allowLowPrecisionAccumulationOnGPU)",
    ]

    if let parameters = configuration.parameters, !parameters.isEmpty {
      let serializedParameters = parameters
        .map { key, value in
          "\(String(describing: key))=\(String(describing: value))"
        }
        .sorted()
        .joined(separator: ",")
      components.append("parameters=\(serializedParameters)")
    }

    return components.joined(separator: "|")
  }

  static func sessionSignalAttributes(
    _ attributes: [String: AttributeValue],
    localOnly: Bool
  ) -> [String: AttributeValue] {
    guard localOnly else { return attributes }
    var attributes = attributes
    attributes[Terra.Keys.Terra.exportLocalOnly] = .bool(true)
    return attributes
  }

  static func featureSummaries(from provider: any MLFeatureProvider) -> [TerraSession.FeatureSummary] {
    provider.featureNames.sorted().compactMap { name in
      guard let value = provider.featureValue(for: name) else { return nil }
      switch value.type {
      case .multiArray:
        let shape = value.multiArrayValue?.shape.map(\.intValue)
        return .init(name: name, kind: "multi_array", shape: shape)
      case .image:
        if let buffer = value.imageBufferValue {
          return .init(
            name: name,
            kind: "image",
            shape: [Int(CVPixelBufferGetHeight(buffer)), Int(CVPixelBufferGetWidth(buffer))]
          )
        }
        return .init(name: name, kind: "image")
      case .dictionary:
        return .init(name: name, kind: "dictionary")
      case .sequence:
        return .init(name: name, kind: "sequence")
      case .string:
        return .init(name: name, kind: "string")
      case .int64:
        return .init(name: name, kind: "int64")
      case .double:
        return .init(name: name, kind: "double")
      case .state:
        return .init(name: name, kind: "state")
      case .invalid:
        return .init(name: name, kind: "invalid")
      @unknown default:
        return .init(name: name, kind: "unknown")
      }
    }
  }

  static func computeUnitsLabel(_ computeUnits: MLComputeUnits) -> String {
    switch computeUnits {
    case .all:
      return "all"
    case .cpuOnly:
      return "cpu_only"
    case .cpuAndGPU:
      return "cpu_and_gpu"
    case .cpuAndNeuralEngine:
      return "cpu_and_ane"
    @unknown default:
      return "unknown"
    }
  }
  #endif

  static func thermalStateLabel(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal:
      return "nominal"
    case .fair:
      return "fair"
    case .serious:
      return "serious"
    case .critical:
      return "critical"
    @unknown default:
      return "unknown"
    }
  }

  static func serializedFeatureSummary(_ summaries: [TerraSession.FeatureSummary]) -> String {
    guard let data = try? JSONEncoder().encode(summaries),
          let string = String(data: data, encoding: .utf8)
    else {
      return "[]"
    }
    return string
  }

  static func monotonicTime() -> UInt64 {
    #if canImport(Darwin)
    return mach_absolute_time()
    #else
    return UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
    #endif
  }

  static func elapsedMilliseconds(since start: UInt64) -> Double {
    #if canImport(Darwin)
    let elapsed = mach_absolute_time() - start
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    let nanos = Double(elapsed) * Double(timebase.numer) / Double(timebase.denom)
    return nanos / 1_000_000
    #else
    return 0
    #endif
  }

  static func capturePhysFootprintBytes() -> UInt64? {
    #if canImport(Darwin)
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
    let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    return info.phys_footprint
    #else
    return nil
    #endif
  }

  static func sha256(_ string: String) -> String {
    #if canImport(CryptoKit)
    let digest = SHA256.hash(data: Data(string.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
    #elseif canImport(Crypto)
    let digest = SHA256.hash(data: Data(string.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
    #else
    return string
    #endif
  }

  static func recordCoreMLError(on span: any Span, error: any Error, at date: Date) {
    let typeName = String(reflecting: type(of: error))
    span.setAttribute(key: "terra.coreml.error_type", value: .string(typeName))
    span.status = .error(description: typeName)
    span.addEvent(
      name: "exception",
      attributes: [
        "exception.type": .string(typeName),
      ],
      timestamp: date
    )
  }
}

private struct TerraSessionOSLogger: TerraSessionLogging {
  func warning(_ message: String) {
    NSLog("TerraSession warning: %@", message)
  }

  func error(_ message: String) {
    NSLog("TerraSession error: %@", message)
  }
}
