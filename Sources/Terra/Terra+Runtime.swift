import Foundation
import OpenTelemetryApi

#if canImport(CryptoKit)
  import CryptoKit
#elseif canImport(Crypto)
  import Crypto
#endif

extension Terra {
  public struct TelemetryConfiguration: Sendable, Hashable {
    public struct RecommendationPolicy: Sendable, Hashable {
      public var enabled: Bool
      public var minConfidence: Double
      public var cooldownSeconds: TimeInterval
      public var dedupeWindowSeconds: TimeInterval
      public var maxTrackedRecommendationIDs: Int

      public init(
        enabled: Bool = true,
        minConfidence: Double = 0.55,
        cooldownSeconds: TimeInterval = 5,
        dedupeWindowSeconds: TimeInterval = 60,
        maxTrackedRecommendationIDs: Int = 512
      ) {
        self.enabled = enabled
        self.minConfidence = min(max(minConfidence, 0), 1)
        self.cooldownSeconds = max(cooldownSeconds, 0)
        self.dedupeWindowSeconds = max(dedupeWindowSeconds, 0)
        self.maxTrackedRecommendationIDs = max(maxTrackedRecommendationIDs, 1)
      }
    }

    public struct TokenLifecyclePolicy: Sendable, Hashable {
      public var enabled: Bool
      public var sampleEveryN: Int
      public var maxEventsPerSpan: Int

      public init(
        enabled: Bool = true,
        sampleEveryN: Int = 1,
        maxEventsPerSpan: Int = 2_000
      ) {
        self.enabled = enabled
        self.sampleEveryN = max(sampleEveryN, 1)
        self.maxEventsPerSpan = max(maxEventsPerSpan, 0)
      }
    }

    public struct KillSwitches: Sendable, Hashable {
      public var tokenLifecycleEnabled: Bool
      public var anomalyEngineEnabled: Bool
      public var deepHardwareSamplingEnabled: Bool

      public init(
        tokenLifecycleEnabled: Bool = true,
        anomalyEngineEnabled: Bool = true,
        deepHardwareSamplingEnabled: Bool = true
      ) {
        self.tokenLifecycleEnabled = tokenLifecycleEnabled
        self.anomalyEngineEnabled = anomalyEngineEnabled
        self.deepHardwareSamplingEnabled = deepHardwareSamplingEnabled
      }
    }

    public var semanticVersion: SemanticVersion
    public var schemaFamily: String
    public var defaultRuntime: RuntimeKind
    public var defaultFingerprintModelID: String
    public var controlLoopMode: String
    public var eventAggregationLevel: String
    public var tokenLifecycle: TokenLifecyclePolicy
    public var recommendationPolicy: RecommendationPolicy
    public var killSwitches: KillSwitches
    public var recommendationOnly: Bool

    public init(
      semanticVersion: SemanticVersion = .v1,
      schemaFamily: String = "terra",
      defaultRuntime: RuntimeKind = .httpAPI,
      defaultFingerprintModelID: String = "unavailable",
      controlLoopMode: String = "deterministic",
      eventAggregationLevel: String = "sampled",
      tokenLifecycle: TokenLifecyclePolicy = .init(),
      recommendationPolicy: RecommendationPolicy = .init(),
      killSwitches: KillSwitches = .init(),
      recommendationOnly: Bool = true
    ) {
      self.semanticVersion = semanticVersion
      self.schemaFamily = schemaFamily
      self.defaultRuntime = defaultRuntime
      self.defaultFingerprintModelID = defaultFingerprintModelID
      self.controlLoopMode = controlLoopMode
      self.eventAggregationLevel = eventAggregationLevel
      self.tokenLifecycle = tokenLifecycle
      self.recommendationPolicy = recommendationPolicy
      self.killSwitches = killSwitches
      self.recommendationOnly = recommendationOnly
    }

    public static let `default` = TelemetryConfiguration()
  }

  public struct Installation {
    public var privacy: Privacy
    public var compliance: CompliancePolicy
    public var telemetry: TelemetryConfiguration
    public var recommendationSink: RecommendationSink?
    public var meterProvider: (any MeterProvider)?
    public var tracerProvider: (any TracerProvider)?
    public var loggerProvider: (any LoggerProvider)?
    public var registerProvidersAsGlobal: Bool

    public init(
      privacy: Privacy = .default,
      compliance: CompliancePolicy = .default,
      telemetry: TelemetryConfiguration = .default,
      recommendationSink: RecommendationSink? = nil,
      meterProvider: (any MeterProvider)? = nil,
      tracerProvider: (any TracerProvider)? = nil,
      loggerProvider: (any LoggerProvider)? = nil,
      registerProvidersAsGlobal: Bool = true
    ) {
      self.privacy = privacy
      self.compliance = compliance
      self.telemetry = telemetry
      self.recommendationSink = recommendationSink
      self.meterProvider = meterProvider
      self.tracerProvider = tracerProvider
      self.loggerProvider = loggerProvider
      self.registerProvidersAsGlobal = registerProvidersAsGlobal
    }
  }
}

final class Runtime {
  static let shared = Runtime()

  private let lock = NSLock()
  private var privacyValue: Terra.Privacy = .default
  private var complianceValue: Terra.CompliancePolicy = .default
  private var telemetryValue: Terra.TelemetryConfiguration = .default
  private var recommendationSinkValue: Terra.RecommendationSink?
  private var tracerProviderOverride: (any TracerProvider)?
  private var loggerProviderOverride: (any LoggerProvider)?
  private var auditEvents: [Terra.AuditEvent] = []
  private var recommendationLastEmitAt: Date?
  private var recommendationLastEmitAtByID: [String: Date] = [:]
  private let runtimeSessionID = UUID().uuidString
  private let maxBufferedAuditEvents = 1_024

  let metrics = TerraMetrics()

  private init() {}

  func install(_ installation: Terra.Installation) {
    lock.lock()
    defer { lock.unlock() }
    privacyValue = installation.privacy
    complianceValue = installation.compliance
    telemetryValue = installation.telemetry
    recommendationSinkValue = installation.recommendationSink
    recommendationLastEmitAt = nil
    recommendationLastEmitAtByID.removeAll(keepingCapacity: true)
    if let tracerProvider = installation.tracerProvider {
      tracerProviderOverride = tracerProvider
    }
    if let loggerProvider = installation.loggerProvider {
      loggerProviderOverride = loggerProvider
    }

    if installation.registerProvidersAsGlobal {
      if let tracerProvider = installation.tracerProvider {
        OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
      }
      if let loggerProvider = installation.loggerProvider {
        OpenTelemetry.registerLoggerProvider(loggerProvider: loggerProvider)
      }
      if let meterProvider = installation.meterProvider {
        OpenTelemetry.registerMeterProvider(meterProvider: meterProvider)
      }
    }

    if let meterProvider = installation.meterProvider {
      metrics.configure(meterProvider: meterProvider)
    }
  }

  var privacy: Terra.Privacy {
    lock.lock()
    defer { lock.unlock() }
    return privacyValue
  }

  var compliance: Terra.CompliancePolicy {
    lock.lock()
    defer { lock.unlock() }
    return complianceValue
  }

  var telemetry: Terra.TelemetryConfiguration {
    lock.lock()
    defer { lock.unlock() }
    return telemetryValue
  }

  var recommendationSink: Terra.RecommendationSink? {
    lock.lock()
    defer { lock.unlock() }
    return recommendationSinkValue
  }

  var tracerProvider: (any TracerProvider)? {
    lock.lock()
    defer { lock.unlock() }
    return tracerProviderOverride
  }

  var loggerProvider: (any LoggerProvider)? {
    lock.lock()
    defer { lock.unlock() }
    return loggerProviderOverride
  }

  var sessionID: String { runtimeSessionID }

  func appendAudit(_ event: Terra.AuditEvent) {
    lock.lock()
    defer { lock.unlock() }
    if auditEvents.count >= maxBufferedAuditEvents {
      auditEvents.removeFirst(auditEvents.count - maxBufferedAuditEvents + 1)
    }
    auditEvents.append(event)
  }

  func consumeAuditEvents() -> [Terra.AuditEvent] {
    lock.lock()
    defer { lock.unlock() }
    let events = auditEvents
    auditEvents.removeAll(keepingCapacity: true)
    return events
  }

  func shouldEmitRecommendation(
    id: String,
    confidence: Double,
    now: Date = Date()
  ) -> Bool {
    lock.lock()
    defer { lock.unlock() }

    let policy = telemetryValue.recommendationPolicy
    guard policy.enabled else { return false }
    guard confidence >= policy.minConfidence else { return false }

    if let recommendationLastEmitAt,
       now.timeIntervalSince(recommendationLastEmitAt) < policy.cooldownSeconds {
      return false
    }

    if let lastForID = recommendationLastEmitAtByID[id],
       now.timeIntervalSince(lastForID) < policy.dedupeWindowSeconds {
      return false
    }

    recommendationLastEmitAt = now
    recommendationLastEmitAtByID[id] = now
    trimRecommendationBuffer(maxTrackedIDs: policy.maxTrackedRecommendationIDs)
    return true
  }

  private func trimRecommendationBuffer(maxTrackedIDs: Int) {
    guard recommendationLastEmitAtByID.count > maxTrackedIDs else { return }
    let overflow = recommendationLastEmitAtByID.count - maxTrackedIDs
    let oldest = recommendationLastEmitAtByID
      .sorted { $0.value < $1.value }
      .prefix(overflow)
      .map(\.key)
    for key in oldest {
      recommendationLastEmitAtByID.removeValue(forKey: key)
    }
  }

  static func sha256Hex(_ string: String) -> String? {
    #if canImport(CryptoKit) || canImport(Crypto)
      let digest = SHA256.hash(data: Data(string.utf8))
      return digest.map { String(format: "%02x", $0) }.joined()
    #else
      return nil
    #endif
  }

  static func anonymizationKeyID(at date: Date = Date()) -> String? {
    let policy = Runtime.shared.privacy.anonymizationPolicy
    guard policy.enabled else { return nil }
    return policy.keyID(for: date)
  }

  static func anonymizedHash(
    of value: String,
    for purpose: String,
    at date: Date = Date()
  ) -> String? {
    let policy = Runtime.shared.privacy.anonymizationPolicy
    guard policy.enabled else { return nil }

    let secret = policy.secret(for: date)
    let payload = "\(purpose)|\(value)"
    #if canImport(CryptoKit)
    let key = SymmetricKey(data: Data(secret.utf8))
    let signature = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
    return signature.compactMap { String(format: "%02x", $0) }.joined()
    #else
    return sha256Hex("\(secret)|\(payload)")
    #endif
  }

  static var isSHA256Available: Bool {
    #if canImport(CryptoKit) || canImport(Crypto)
      return true
    #else
      return false
    #endif
  }

  static func thermalStateLabel() -> String {
    switch ProcessInfo.processInfo.thermalState {
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
}

final class TerraMetrics {
  private let lock = NSLock()
  private var inferenceCount: LongCounter?
  private var inferenceDurationMs: DoubleHistogram?
  private var recommendationCount: LongCounter?
  private var anomalyCount: LongCounter?
  private var stalledTokenCount: LongCounter?

  func configure(meterProvider: (any MeterProvider)?) {
    lock.lock()
    defer { lock.unlock() }

    guard let meterProvider else {
      inferenceCount = nil
      inferenceDurationMs = nil
      recommendationCount = nil
      anomalyCount = nil
      stalledTokenCount = nil
      return
    }

    let meter = meterProvider.get(name: Terra.instrumentationName)
    inferenceCount = meter.counterBuilder(name: Terra.MetricNames.inferenceCount).build()
    inferenceDurationMs = meter.histogramBuilder(name: Terra.MetricNames.inferenceDurationMs).build()
    recommendationCount = meter.counterBuilder(name: Terra.MetricNames.recommendationCount).build()
    anomalyCount = meter.counterBuilder(name: Terra.MetricNames.anomalyCount).build()
    stalledTokenCount = meter.counterBuilder(name: Terra.MetricNames.stalledTokenCount).build()
  }

  func recordInference(durationMs: Double) {
    // Copy references under the lock. OTel SDK instruments are thread-safe,
    // so we release the lock before calling add/record to avoid holding it
    // across external SDK calls (which could introduce lock-ordering issues).
    // `var` is required because add/record are mutating on protocol existentials.
    lock.lock()
    var inferenceCount = inferenceCount
    var inferenceDurationMs = inferenceDurationMs
    lock.unlock()

    inferenceCount?.add(value: 1, attributes: [:])
    inferenceDurationMs?.record(value: durationMs, attributes: [:])
  }

  func recordRecommendation() {
    lock.lock()
    var recommendationCount = recommendationCount
    lock.unlock()
    recommendationCount?.add(value: 1, attributes: [:])
  }

  func recordAnomaly(kind: String) {
    lock.lock()
    var anomalyCount = anomalyCount
    var stalledTokenCount = stalledTokenCount
    lock.unlock()

    anomalyCount?.add(value: 1, attributes: [Terra.Keys.Terra.anomalyKind: .string(kind)])
    if kind == "stalled_token" {
      stalledTokenCount?.add(value: 1, attributes: [:])
    }
  }
}
