import Foundation
import OpenTelemetryApi

#if canImport(CryptoKit)
  import CryptoKit
#elseif canImport(Crypto)
  import Crypto
#endif

#if canImport(Security)
  import Security
#endif

extension Terra {
  /// The lifecycle state of the Terra runtime.
  ///
  /// - Note: During `installOpenTelemetry()`, there is a brief window where
  ///   `installedOpenTelemetryConfiguration` is committed but `lifecycleState`
  ///   still reports `.stopped`. Do not use `lifecycleState` as a strict
  ///   proxy for whether a configuration is active across concurrent contexts.
  public enum LifecycleState: Sendable, Equatable {
    /// Terra has not been started, or has been shut down. `Terra.start()` may be called.
    case stopped

    /// Terra is starting. A start/reconfigure call is in progress.
    case starting

    /// Terra is running. Telemetry is being collected and exported.
    case running

    /// Terra is shutting down. A shutdown/reset/reconfigure call is in progress.
    case shuttingDown
  }
}

extension Terra {
  package struct Installation {
    package var privacy: Privacy
    package var meterProvider: (any MeterProvider)?
    package var tracerProvider: (any TracerProvider)?
    package var loggerProvider: (any LoggerProvider)?
    package var registerProvidersAsGlobal: Bool

    package init(
      privacy: Privacy = .default,
      meterProvider: (any MeterProvider)? = nil,
      tracerProvider: (any TracerProvider)? = nil,
      loggerProvider: (any LoggerProvider)? = nil,
      registerProvidersAsGlobal: Bool = true
    ) {
      self.privacy = privacy
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
  private var tracerProviderOverride: (any TracerProvider)?
  private var loggerProviderOverride: (any LoggerProvider)?
  private var anonymizationKey: Data
  private var anonymizationKeyID: String

  let metrics = TerraMetrics()

  // MARK: - Lifecycle

  private var lifecycleStateValue: Terra.LifecycleState = .stopped

  var lifecycleState: Terra.LifecycleState {
    lock.lock()
    defer { lock.unlock() }
    return lifecycleStateValue
  }

  func markStarting() {
    lock.lock()
    defer { lock.unlock() }
    lifecycleStateValue = .starting
  }

  func markRunning() {
    lock.lock()
    defer { lock.unlock() }
    lifecycleStateValue = .running
  }

  func markShuttingDown() {
    lock.lock()
    defer { lock.unlock() }
    lifecycleStateValue = .shuttingDown
  }

  func markStopped() {
    lock.lock()
    defer { lock.unlock() }
    lifecycleStateValue = .stopped
    privacyValue = .default
    tracerProviderOverride = nil
    loggerProviderOverride = nil
    let key = Runtime.loadOrCreateAnonymizationKey()
    anonymizationKey = key
    anonymizationKeyID = Runtime.deriveAnonymizationKeyID(from: key)
  }

  private init() {
    let key = Runtime.loadOrCreateAnonymizationKey()
    anonymizationKey = key
    anonymizationKeyID = Runtime.deriveAnonymizationKeyID(from: key)
  }

  func install(_ installation: Terra.Installation) {
    lock.lock()
    defer { lock.unlock() }
    privacyValue = installation.privacy
    if let providedAnonymizationKey = installation.privacy.anonymizationKey {
      anonymizationKey = providedAnonymizationKey
      anonymizationKeyID = Runtime.deriveAnonymizationKeyID(from: providedAnonymizationKey)
    }
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

  var anonymizationKeyIDValue: String? {
    #if canImport(CryptoKit) || canImport(Crypto)
      lock.lock()
      defer { lock.unlock() }
      return anonymizationKeyID
    #else
      return nil
    #endif
  }

  func hmacSHA256Hex(_ string: String) -> String? {
    #if canImport(CryptoKit) || canImport(Crypto)
      lock.lock()
      let key = anonymizationKey
      lock.unlock()
      return Runtime.hmacSHA256Hex(string, key: key)
    #else
      return nil
    #endif
  }

  static func sha256Hex(_ string: String) -> String? {
    sha256Hex(data: Data(string.utf8))
  }

  static func sha256Hex(data: Data) -> String? {
    #if canImport(CryptoKit) || canImport(Crypto)
      let digest = SHA256.hash(data: data)
      return digest.map { String(format: "%02x", $0) }.joined()
    #else
      return nil
    #endif
  }

  static func hmacSHA256Hex(_ string: String, key: Data) -> String? {
    #if canImport(CryptoKit) || canImport(Crypto)
      let symmetricKey = SymmetricKey(data: key)
      let mac = HMAC<SHA256>.authenticationCode(for: Data(string.utf8), using: symmetricKey)
      return Data(mac).map { String(format: "%02x", $0) }.joined()
    #else
      return nil
    #endif
  }

  static var isSHA256Available: Bool {
    #if canImport(CryptoKit) || canImport(Crypto)
      return true
    #else
      return false
    #endif
  }

  static var isHMACSHA256Available: Bool {
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

private extension Runtime {
  static let anonymizationKeyLengthBytes = 32
  static let anonymizationKeychainService = "io.opentelemetry.terra"
  static let anonymizationKeychainAccount = "anonymization.hmac_sha256"

  static func loadOrCreateAnonymizationKey() -> Data {
    if let existing = readAnonymizationKeyFromKeychain() {
      return existing
    }
    let generated = generateAnonymizationKey()
    _ = storeAnonymizationKeyToKeychain(generated)
    return generated
  }

  static func deriveAnonymizationKeyID(from key: Data) -> String {
    guard let digest = sha256Hex(data: key) else { return "unknown" }
    return String(digest.prefix(16))
  }

  static func generateAnonymizationKey() -> Data {
    #if canImport(Security)
      var bytes = [UInt8](repeating: 0, count: anonymizationKeyLengthBytes)
      let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
      if status == errSecSuccess {
        return Data(bytes)
      }
    #endif
    let seed = UUID().uuidString + UUID().uuidString
    return Data(Data(seed.utf8).prefix(anonymizationKeyLengthBytes))
  }

  static func readAnonymizationKeyFromKeychain() -> Data? {
    #if canImport(Security)
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: anonymizationKeychainService,
        kSecAttrAccount as String: anonymizationKeychainAccount,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ]
      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      guard status == errSecSuccess else { return nil }
      return result as? Data
    #else
      return nil
    #endif
  }

  static func storeAnonymizationKeyToKeychain(_ key: Data) -> Bool {
    #if canImport(Security)
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: anonymizationKeychainService,
        kSecAttrAccount as String: anonymizationKeychainAccount,
      ]
      let attributes: [String: Any] = [
        kSecValueData as String: key,
      ]
      let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
      if updateStatus == errSecSuccess {
        return true
      }
      if updateStatus != errSecItemNotFound {
        return false
      }
      var create = query
      create[kSecValueData as String] = key
      return SecItemAdd(create as CFDictionary, nil) == errSecSuccess
    #else
      return false
    #endif
  }
}

final class TerraMetrics {
  private let lock = NSLock()
  private var inferenceCount: LongCounter?
  private var inferenceDurationMs: DoubleHistogram?

  func configure(meterProvider: (any MeterProvider)?) {
    lock.lock()
    defer { lock.unlock() }

    guard let meterProvider else {
      inferenceCount = nil
      inferenceDurationMs = nil
      return
    }

    let meter = meterProvider.get(name: Terra.instrumentationName)
    inferenceCount = meter.counterBuilder(name: Terra.MetricNames.inferenceCount).build()
    inferenceDurationMs = meter.histogramBuilder(name: Terra.MetricNames.inferenceDurationMs).build()
  }

  private static let emptyAttributes: [String: OpenTelemetryApi.AttributeValue] = [:]

  func recordInference(durationMs: Double) {
    // Copy references under the lock. OTel SDK instruments are thread-safe,
    // so we release the lock before calling add/record to avoid holding it
    // across external SDK calls (which could introduce lock-ordering issues).
    // `var` is required because add/record are mutating on protocol existentials.
    lock.lock()
    var inferenceCount = inferenceCount
    var inferenceDurationMs = inferenceDurationMs
    lock.unlock()

    inferenceCount?.add(value: 1, attributes: Self.emptyAttributes)
    inferenceDurationMs?.record(value: durationMs, attributes: Self.emptyAttributes)
  }
}
