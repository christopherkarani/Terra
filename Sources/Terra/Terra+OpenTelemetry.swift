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
      otlpTracesEndpoint: URL = defaultOtlpHttpTracesEndpoint(),
      otlpMetricsEndpoint: URL = defaultOtlpHttpMetricsEndpoint(),
      otlpLogsEndpoint: URL = defaultOtlpHttpLogsEndpoint(),
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

  public static func defaultOtlpHttpTracesEndpoint() -> URL {
    URL(string: "http://localhost:4318/v1/traces")!
  }

  public static func defaultOtlpHttpMetricsEndpoint() -> URL {
    URL(string: "http://localhost:4318/v1/metrics")!
  }

  public static func defaultOtlpHttpLogsEndpoint() -> URL {
    URL(string: "http://localhost:4318/v1/logs")!
  }

  @available(*, deprecated, renamed: "defaultOtlpHttpTracesEndpoint")
  public static func defaultOltpHttpTracesEndpoint() -> URL {
    defaultOtlpHttpTracesEndpoint()
  }

  @available(*, deprecated, renamed: "defaultOtlpHttpMetricsEndpoint")
  public static func defaultOltpHttpMetricsEndpoint() -> URL {
    defaultOtlpHttpMetricsEndpoint()
  }

  @available(*, deprecated, renamed: "defaultOtlpHttpLogsEndpoint")
  public static func defaultOltpHttpLoggingEndpoint() -> URL {
    defaultOtlpHttpLogsEndpoint()
  }

  public enum InstallOpenTelemetryError: Error {
    case alreadyInstalled
  }

  private static let openTelemetryInstallLock = NSLock()
  private static var installedOpenTelemetryConfiguration: OpenTelemetryConfiguration?

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
    let normalizedConfiguration = normalize(configuration)

    if let installed = installedOpenTelemetryConfiguration {
      if installed == normalizedConfiguration {
        return
      }
      throw InstallOpenTelemetryError.alreadyInstalled
    }
    let previousTracerProvider = OpenTelemetry.instance.tracerProvider
    let previousMeterProvider = OpenTelemetry.instance.meterProvider
    let previousLoggerProvider = OpenTelemetry.instance.loggerProvider

    do {
      if let persistence = normalizedConfiguration.persistence {
        try FileManager.default.createDirectory(at: persistence.storageURL, withIntermediateDirectories: true, attributes: nil)
      }

      let tracerProvider = try installTracing(configuration: normalizedConfiguration)

      if normalizedConfiguration.enableSignposts, let tracerProviderSdk = tracerProvider as? TracerProviderSdk {
        installSignposts(tracerProviderSdk: tracerProviderSdk)
      }

      if normalizedConfiguration.enableLogs {
        _ = try installLogs(configuration: normalizedConfiguration)
      }

      if normalizedConfiguration.enableSessions, let tracerProviderSdk = tracerProvider as? TracerProviderSdk {
        tracerProviderSdk.addSpanProcessor(TerraSessionSpanProcessor())
        SessionEventInstrumentation.install()
      }

      if normalizedConfiguration.enableMetrics {
        let meterProvider = try installMetrics(configuration: normalizedConfiguration)
        Terra.install(.init(privacy: Runtime.shared.privacy, meterProvider: meterProvider, registerProvidersAsGlobal: false))
      }
      installedOpenTelemetryConfiguration = normalizedConfiguration
    } catch {
      installedOpenTelemetryConfiguration = nil
      OpenTelemetry.registerTracerProvider(tracerProvider: previousTracerProvider)
      OpenTelemetry.registerMeterProvider(meterProvider: previousMeterProvider)
      OpenTelemetry.registerLoggerProvider(loggerProvider: previousLoggerProvider)
      throw error
    }
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

  private static func installTracing(configuration: OpenTelemetryConfiguration) throws -> any TracerProvider {
    guard configuration.enableTraces else {
      let provider = DefaultTracerProvider.instance
      OpenTelemetry.registerTracerProvider(tracerProvider: provider)
      return provider
    }

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

    let exporter = try makeExporter()
    let spanProcessor = SimpleSpanProcessor(spanExporter: exporter)
    let resource = makeResource(configuration: configuration)
    let sampler: Sampler?
    if let ratio = configuration.traceSamplingRatio {
      if ratio.isFinite {
        let clamped = min(max(ratio, 0), 1)
        sampler = Samplers.parentBased(root: Samplers.traceIdRatio(ratio: clamped))
      } else {
        sampler = nil
      }
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
        existing.addSpanProcessor(spanProcessor)
        return existing
      }
      fallthrough
    case .registerNew:
      var builder = TracerProviderBuilder()
      builder = builder.with(resource: resource)
      if let sampler {
        builder = builder.with(sampler: sampler)
      }
      builder = builder.add(spanProcessor: TerraSpanEnrichmentProcessor())
      builder = builder.add(spanProcessor: spanProcessor)
      let provider = builder.build()
      OpenTelemetry.registerTracerProvider(tracerProvider: provider)
      return provider
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

  private static func normalize(_ configuration: OpenTelemetryConfiguration) -> OpenTelemetryConfiguration {
    var normalized = configuration
    if let ratio = normalized.traceSamplingRatio {
      if ratio.isFinite {
        normalized.traceSamplingRatio = min(max(ratio, 0), 1)
      } else {
        normalized.traceSamplingRatio = nil
      }
    }
    return normalized
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

  private static func installLogs(configuration: OpenTelemetryConfiguration) throws -> LoggerProviderSdk {
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
    return provider
  }
}

#if DEBUG
extension Terra {
  static func resetOpenTelemetryForTesting() {
    openTelemetryInstallLock.lock()
    defer { openTelemetryInstallLock.unlock() }
    installedOpenTelemetryConfiguration = nil
  }
}
#endif
