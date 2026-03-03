import Foundation
import OpenTelemetryApi
import OpenTelemetryProtocolExporterHttp
import OpenTelemetrySdk
import PersistenceExporter
import Sessions

#if canImport(SignPostIntegration)
  import SignPostIntegration
#endif

extension Terra {
  public enum TracerProviderStrategy: Equatable {
    /// Register new providers globally (recommended for first-time adopters).
    case registerNew
    /// Attempt to augment existing global providers; falls back to `registerNew` when unsupported.
    case augmentExisting
  }

  public struct OpenTelemetryConfiguration: Equatable {
    public var tracerProviderStrategy: TracerProviderStrategy

    public var enableTraces: Bool
    public var enableMetrics: Bool
    public var enableLogs: Bool

    public var enableSignposts: Bool
    public var enableSessions: Bool

    public var otlpTracesEndpoint: URL
    public var otlpMetricsEndpoint: URL
    public var otlpLogsEndpoint: URL

    public var metricsExportInterval: TimeInterval

    public var persistence: PersistenceConfiguration?
    public var serviceName: String?
    public var serviceVersion: String?
    public var resourceAttributes: [String: AttributeValue]
    public var traceSamplingRatio: Double?

    public init(
      tracerProviderStrategy: TracerProviderStrategy = .registerNew,
      enableTraces: Bool = true,
      enableMetrics: Bool = true,
      enableLogs: Bool = false,
      enableSignposts: Bool = true,
      enableSessions: Bool = true,
      otlpTracesEndpoint: URL = defaultOltpHttpTracesEndpoint(),
      otlpMetricsEndpoint: URL = defaultOtlpHttpMetricsEndpoint(),
      otlpLogsEndpoint: URL = defaultOltpHttpLoggingEndpoint(),
      metricsExportInterval: TimeInterval = 60,
      persistence: PersistenceConfiguration? = nil,
      serviceName: String? = nil,
      serviceVersion: String? = nil,
      resourceAttributes: [String: AttributeValue] = [:],
      traceSamplingRatio: Double? = nil
    ) {
      self.tracerProviderStrategy = tracerProviderStrategy
      self.enableTraces = enableTraces
      self.enableMetrics = enableMetrics
      self.enableLogs = enableLogs
      self.enableSignposts = enableSignposts
      self.enableSessions = enableSessions
      self.otlpTracesEndpoint = otlpTracesEndpoint
      self.otlpMetricsEndpoint = otlpMetricsEndpoint
      self.otlpLogsEndpoint = otlpLogsEndpoint
      self.metricsExportInterval = metricsExportInterval
      self.persistence = persistence
      self.serviceName = serviceName
      self.serviceVersion = serviceVersion
      self.resourceAttributes = resourceAttributes
      self.traceSamplingRatio = traceSamplingRatio
    }
  }

  public struct PersistenceConfiguration: Equatable {
    public var storageURL: URL
    public var performancePreset: PersistencePerformancePreset

    public init(
      storageURL: URL = Terra.defaultPersistenceStorageURL(),
      performancePreset: PersistencePerformancePreset = .default
    ) {
      self.storageURL = storageURL
      self.performancePreset = performancePreset
    }

    public var tracesStorageURL: URL {
      storageURL.appendingPathComponent("traces", isDirectory: true)
    }

    public var metricsStorageURL: URL {
      storageURL.appendingPathComponent("metrics", isDirectory: true)
    }

    public var logsStorageURL: URL {
      storageURL.appendingPathComponent("logs", isDirectory: true)
    }
  }

  public static func defaultPersistenceStorageURL() -> URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base
      .appendingPathComponent("opentelemetry", isDirectory: true)
      .appendingPathComponent("terra", isDirectory: true)
  }

  public enum InstallOpenTelemetryError: Error {
    case alreadyInstalled
  }

  private static let openTelemetryInstallLock = NSLock()
  private static var installedOpenTelemetryConfiguration: OpenTelemetryConfiguration?
  private static var installedTracerProvider: TracerProviderSdk?
  private static var installedMeterProvider: MeterProviderSdk?
  private static var installedLogProcessor: (any LogRecordProcessor)?
  private static var ownsInstalledTracerProvider: Bool = false

  /// Convenience for end-to-end OpenTelemetry wiring:
  /// - Traces exported via OTLP/HTTP (optionally persisted on-device).
  /// - Metrics exported via OTLP/HTTP (optionally persisted on-device).
  /// - Signposts enabled so spans appear in Instruments (when supported).
  /// - Sessions enabled so session IDs are attached to spans (optional).
  ///
  /// This configures global OpenTelemetry providers and also configures Terra's internal meter usage.
  ///
  /// - Throws: `InstallOpenTelemetryError.alreadyInstalled` if called more than once with a different configuration.
  public static func installOpenTelemetry(_ configuration: OpenTelemetryConfiguration) throws {
    openTelemetryInstallLock.lock()
    defer { openTelemetryInstallLock.unlock() }

    if let installed = installedOpenTelemetryConfiguration {
      if installed == configuration {
        return
      }
      throw InstallOpenTelemetryError.alreadyInstalled
    }

    installedOpenTelemetryConfiguration = configuration

    do {
      if let persistence = configuration.persistence {
        try FileManager.default.createDirectory(at: persistence.storageURL, withIntermediateDirectories: true, attributes: nil)
      }

      let (tracerProviderSdk, ownsTracer) = try installTracing(configuration: configuration)
      installedTracerProvider = tracerProviderSdk
      ownsInstalledTracerProvider = ownsTracer

      if configuration.enableSignposts {
        installSignposts(tracerProviderSdk: tracerProviderSdk)
      }

      if configuration.enableLogs {
        let (_, logProcessor) = try installLogs(configuration: configuration)
        installedLogProcessor = logProcessor
      }

      if configuration.enableSessions {
        tracerProviderSdk.addSpanProcessor(TerraSessionSpanProcessor())
        SessionEventInstrumentation.install()
      }

      if configuration.enableMetrics {
        let meterProvider = try installMetrics(configuration: configuration)
        installedMeterProvider = meterProvider
        Terra.install(.init(privacy: Runtime.shared.privacy, meterProvider: meterProvider, registerProvidersAsGlobal: false))
      }
    } catch {
      installedOpenTelemetryConfiguration = nil
      installedTracerProvider = nil
      installedMeterProvider = nil
      installedLogProcessor = nil
      ownsInstalledTracerProvider = false
      throw error
    }

    Runtime.shared.markRunning()
  }

  // MARK: - Tracing

  private static func makeResource(configuration: OpenTelemetryConfiguration) -> Resource {
    var attributes = configuration.resourceAttributes
    if let serviceName = configuration.serviceName, !serviceName.isEmpty {
      attributes["service.name"] = .string(serviceName)
    }
    if let serviceVersion = configuration.serviceVersion, !serviceVersion.isEmpty {
      attributes["service.version"] = .string(serviceVersion)
    }
    return Resource(attributes: attributes)
  }

  private static func installTracing(configuration: OpenTelemetryConfiguration) throws -> (TracerProviderSdk, Bool) {
    func makeExporter() throws -> any SpanExporter {
      let baseExporter = OtlpHttpTraceExporter(endpoint: configuration.otlpTracesEndpoint)
      guard let persistence = configuration.persistence else {
        return baseExporter
      }
      try FileManager.default.createDirectory(at: persistence.tracesStorageURL, withIntermediateDirectories: true, attributes: nil)
      return try PersistenceSpanExporterDecorator(
        spanExporter: baseExporter,
        storageURL: persistence.tracesStorageURL,
        performancePreset: persistence.performancePreset
      )
    }

    let spanProcessor: SpanProcessor?
    if configuration.enableTraces {
      let exporter = try makeExporter()
      spanProcessor = SimpleSpanProcessor(spanExporter: exporter)
    } else {
      spanProcessor = nil
    }
    let resource = makeResource(configuration: configuration)
    let sampler: Sampler?
    if let ratio = configuration.traceSamplingRatio {
      let clamped = min(max(ratio, 0), 1)
      sampler = Samplers.parentBased(root: Samplers.traceIdRatio(ratio: clamped))
    } else {
      sampler = nil
    }

    switch configuration.tracerProviderStrategy {
    case .augmentExisting:
      if let existing = OpenTelemetry.instance.tracerProvider as? TracerProviderSdk {
        existing.updateActiveResource(existing.getActiveResource().merging(other: resource))
        if let sampler {
          existing.updateActiveSampler(sampler)
        }
        existing.addSpanProcessor(TerraSpanEnrichmentProcessor())
        if let spanProcessor {
          existing.addSpanProcessor(spanProcessor)
        }
        return (existing, false)
      }
      fallthrough
    case .registerNew:
      var builder = TracerProviderBuilder()
      builder = builder.with(resource: resource)
      if let sampler {
        builder = builder.with(sampler: sampler)
      }
      builder = builder.add(spanProcessor: TerraSpanEnrichmentProcessor())
      if let spanProcessor {
        builder = builder.add(spanProcessor: spanProcessor)
      }
      let provider = builder.build()
      OpenTelemetry.registerTracerProvider(tracerProvider: provider)
      return (provider, true)
    }
  }

  private static func installSignposts(tracerProviderSdk: TracerProviderSdk) {
    #if canImport(SignPostIntegration)
      if #available(iOS 15.0, macOS 12, tvOS 15.0, watchOS 8.0, *) {
        tracerProviderSdk.addSpanProcessor(OSSignposterIntegration())
      } else {
        #if !os(watchOS) && !os(visionOS)
          tracerProviderSdk.addSpanProcessor(SignPostIntegration())
        #endif
      }
    #else
      _ = tracerProviderSdk
    #endif
  }

  // MARK: - Metrics

  private static func installMetrics(configuration: OpenTelemetryConfiguration) throws -> MeterProviderSdk {
    func makeExporter() throws -> any MetricExporter {
      let baseExporter = OtlpHttpMetricExporter(endpoint: configuration.otlpMetricsEndpoint)
      guard let persistence = configuration.persistence else {
        return baseExporter
      }
      try FileManager.default.createDirectory(at: persistence.metricsStorageURL, withIntermediateDirectories: true, attributes: nil)
      return try PersistenceMetricExporterDecorator(
        metricExporter: baseExporter,
        storageURL: persistence.metricsStorageURL,
        performancePreset: persistence.performancePreset
      )
    }

    let exporter = try makeExporter()
    let reader = PeriodicMetricReaderBuilder(exporter: exporter)
      .setInterval(timeInterval: configuration.metricsExportInterval)
      .build()

    let resource = makeResource(configuration: configuration)
    let provider = MeterProviderSdk.builder()
      .setResource(resource: resource)
      .registerMetricReader(reader: reader)
      .registerView(selector: InstrumentSelectorBuilder().build(), view: View.builder().build())
      .build()

    OpenTelemetry.registerMeterProvider(meterProvider: provider)
    return provider
  }

  // MARK: - Logs

  private static func installLogs(configuration: OpenTelemetryConfiguration) throws -> (LoggerProviderSdk, any LogRecordProcessor) {
    func makeExporter() throws -> any LogRecordExporter {
      let baseExporter = OtlpHttpLogExporter(endpoint: configuration.otlpLogsEndpoint)
      guard let persistence = configuration.persistence else {
        return baseExporter
      }
      try FileManager.default.createDirectory(at: persistence.logsStorageURL, withIntermediateDirectories: true, attributes: nil)
      return try PersistenceLogExporterDecorator(
        logRecordExporter: baseExporter,
        storageURL: persistence.logsStorageURL,
        performancePreset: persistence.performancePreset
      )
    }

    let exporter = try makeExporter()
    let processor = SimpleLogRecordProcessor(logRecordExporter: exporter)
    let resource = makeResource(configuration: configuration)

    let provider = LoggerProviderBuilder()
      .with(resource: resource)
      .with(processors: [processor])
      .build()

    OpenTelemetry.registerLoggerProvider(loggerProvider: provider)
    return (provider, processor)
  }

  // MARK: - Lifecycle Queries

  /// The current lifecycle state of the Terra runtime.
  public static var lifecycleState: Terra.LifecycleState {
    Runtime.shared.lifecycleState
  }

  /// `true` when Terra has been started and is actively collecting telemetry.
  public static var isRunning: Bool {
    lifecycleState == .running
  }

  // MARK: - Shutdown

  /// Shuts down Terra gracefully, resetting the runtime to `.uninitialized`.
  ///
  /// Flushes buffered telemetry to configured exporter(s) and releases provider
  /// resources before returning. After this call, `Terra.installOpenTelemetry()`
  /// / `Terra.start()` may be called again with any configuration.
  ///
  /// Safe to call from any context. Idempotent — calling it when Terra is not
  /// running is a no-op.
  ///
  /// - Note: Flush and shutdown calls are currently synchronous.
  /// - Important: `shutdown()` may block the calling thread briefly while
  ///   flushing telemetry to the configured exporter. Avoid calling from
  ///   latency-sensitive or main-actor contexts in production; a future
  ///   update will make flush fully async.
  public static func shutdown() async {
    _performShutdown()
  }

  /// Synchronous shutdown core — performs all locking and I/O synchronously
  /// with no suspension points, so the lock is never held across an await.
  private static func _performShutdown() {
    openTelemetryInstallLock.lock()
    guard installedOpenTelemetryConfiguration != nil else {
      openTelemetryInstallLock.unlock()
      return
    }
    // Atomically claim ownership of all provider refs before releasing the lock.
    // No other caller can enter after this point — installedOpenTelemetryConfiguration is nil.
    installedOpenTelemetryConfiguration = nil
    let tracerProvider = installedTracerProvider
    let meterProvider = installedMeterProvider
    let logProcessor = installedLogProcessor
    installedTracerProvider = nil
    installedMeterProvider = nil
    installedLogProcessor = nil
    let tracerOwned = ownsInstalledTracerProvider
    ownsInstalledTracerProvider = false
    openTelemetryInstallLock.unlock()

    // Flush and shut down outside the lock — these are potentially blocking I/O.
    // We already own the refs exclusively; the lock is not needed here.
    tracerProvider?.forceFlush()           // safe regardless of ownership
    if tracerOwned { tracerProvider?.shutdown() }
    _ = meterProvider?.forceFlush()
    _ = meterProvider?.shutdown()
    _ = logProcessor?.forceFlush()
    _ = logProcessor?.shutdown()

    Runtime.shared.markUninitialized()
  }
}

#if DEBUG
extension Terra {
  // Tests can lock in one thread and unlock after an async hop on another.
  // DispatchSemaphore avoids thread-affinity lock ownership issues in that path.
  private static let testingIsolationLock = DispatchSemaphore(value: 1)

  public static func lockTestingIsolation() {
    testingIsolationLock.wait()
  }

  public static func unlockTestingIsolation() {
    testingIsolationLock.signal()
  }

  static func resetOpenTelemetryForTesting() {
    openTelemetryInstallLock.lock()
    defer { openTelemetryInstallLock.unlock() }
    installedOpenTelemetryConfiguration = nil
    installedTracerProvider = nil
    installedMeterProvider = nil
    installedLogProcessor = nil
    ownsInstalledTracerProvider = false
    Runtime.shared.markUninitialized()
  }
}
#endif
