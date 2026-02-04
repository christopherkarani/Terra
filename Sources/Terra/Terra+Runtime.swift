import Foundation
import OpenTelemetryApi

#if canImport(CryptoKit)
  import CryptoKit
#elseif canImport(Crypto)
  import Crypto
#endif

extension Terra {
  public struct Installation {
    public var privacy: Privacy
    public var meterProvider: (any MeterProvider)?
    public var tracerProvider: (any TracerProvider)?
    public var loggerProvider: (any LoggerProvider)?
    public var registerProvidersAsGlobal: Bool

    public init(
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

  let metrics = TerraMetrics()

  private init() {}

  func install(_ installation: Terra.Installation) {
    lock.lock()
    privacyValue = installation.privacy
    if let tracerProvider = installation.tracerProvider {
      tracerProviderOverride = tracerProvider
    }
    if let loggerProvider = installation.loggerProvider {
      loggerProviderOverride = loggerProvider
    }
    lock.unlock()

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

  static func sha256Hex(_ string: String) -> String? {
    #if canImport(CryptoKit) || canImport(Crypto)
      let digest = SHA256.hash(data: Data(string.utf8))
      return digest.map { String(format: "%02x", $0) }.joined()
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

  func recordInference(durationMs: Double) {
    lock.lock()
    var inferenceCount = inferenceCount
    var inferenceDurationMs = inferenceDurationMs
    lock.unlock()

    inferenceCount?.add(value: 1, attributes: [:])
    inferenceDurationMs?.record(value: durationMs, attributes: [:])
  }
}
