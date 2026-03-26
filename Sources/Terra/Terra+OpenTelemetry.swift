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
  package enum TracerProviderStrategy: Equatable {
    /// Register new providers globally (recommended for first-time adopters).
    case registerNew
    /// Attempt to augment existing global providers; falls back to `registerNew` when unsupported.
    case augmentExisting
  }

  package struct OpenTelemetryConfiguration: Equatable {
    package var tracerProviderStrategy: TracerProviderStrategy

    package var enableTraces: Bool
    package var enableMetrics: Bool
    package var enableLogs: Bool

    package var enableSignposts: Bool
    package var enableSessions: Bool

    package var otlpTracesEndpoint: URL
    package var otlpMetricsEndpoint: URL
    package var otlpLogsEndpoint: URL

    package var metricsExportInterval: TimeInterval

    package var persistence: PersistenceConfiguration?
    package var serviceName: String?
    package var serviceVersion: String?
    package var resourceAttributes: [String: AttributeValue]
    package var traceSamplingRatio: Double?

    package init(
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

  package struct PersistenceConfiguration: Equatable {
    package var storageURL: URL
    package var performancePreset: PersistencePerformancePreset

    package init(
      storageURL: URL = Terra.defaultPersistenceStorageURL(),
      performancePreset: PersistencePerformancePreset = .default
    ) {
      self.storageURL = storageURL
      self.performancePreset = performancePreset
    }

    package var tracesStorageURL: URL {
      storageURL.appendingPathComponent("traces", isDirectory: true)
    }

    package var metricsStorageURL: URL {
      storageURL.appendingPathComponent("metrics", isDirectory: true)
    }

    package var logsStorageURL: URL {
      storageURL.appendingPathComponent("logs", isDirectory: true)
    }
  }

  package final class SimulatorAwareSpanExporter: SpanExporter {
    private let spanExporter: any SpanExporter
    private let shouldExport: @Sendable () -> Bool

    package init(
      spanExporter: any SpanExporter,
      shouldExport: @escaping @Sendable () -> Bool = { !Terra._isSimulatorExportBlocked }
    ) {
      self.spanExporter = spanExporter
      self.shouldExport = shouldExport
    }

    @discardableResult
    package func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
      guard shouldExport() else { return .success }
      let exportableSpans = spans.filter { span in
        span.attributes[Keys.Terra.exportLocalOnly] != .bool(true)
      }
      guard !exportableSpans.isEmpty else { return .success }
      return spanExporter.export(spans: exportableSpans, explicitTimeout: explicitTimeout)
    }

    package func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
      guard shouldExport() else { return .success }
      return spanExporter.flush(explicitTimeout: explicitTimeout)
    }

    package func shutdown(explicitTimeout: TimeInterval?) {
      spanExporter.shutdown(explicitTimeout: explicitTimeout)
    }
  }

  package final class SimulatorAwareMetricExporter: MetricExporter {
    private let metricExporter: any MetricExporter
    private let shouldExport: @Sendable () -> Bool

    package init(
      metricExporter: any MetricExporter,
      shouldExport: @escaping @Sendable () -> Bool = { !Terra._isSimulatorExportBlocked }
    ) {
      self.metricExporter = metricExporter
      self.shouldExport = shouldExport
    }

    package func export(metrics: [MetricData]) -> ExportResult {
      guard shouldExport() else { return .success }
      return metricExporter.export(metrics: metrics)
    }

    package func flush() -> ExportResult {
      guard shouldExport() else { return .success }
      return metricExporter.flush()
    }

    package func shutdown() -> ExportResult {
      metricExporter.shutdown()
    }

    package func getAggregationTemporality(for instrument: InstrumentType) -> AggregationTemporality {
      metricExporter.getAggregationTemporality(for: instrument)
    }
  }

  package final class SimulatorAwareLogExporter: LogRecordExporter {
    private let logExporter: any LogRecordExporter
    private let shouldExport: @Sendable () -> Bool

    package init(
      logExporter: any LogRecordExporter,
      shouldExport: @escaping @Sendable () -> Bool = { !Terra._isSimulatorExportBlocked }
    ) {
      self.logExporter = logExporter
      self.shouldExport = shouldExport
    }

    package func export(logRecords: [ReadableLogRecord], explicitTimeout: TimeInterval?) -> ExportResult {
      guard shouldExport() else { return .success }
      let exportableLogRecords = logRecords.filter { logRecord in
        logRecord.attributes[Keys.Terra.exportLocalOnly] != .bool(true)
      }
      guard !exportableLogRecords.isEmpty else { return .success }
      return logExporter.export(logRecords: exportableLogRecords, explicitTimeout: explicitTimeout)
    }

    package func shutdown(explicitTimeout: TimeInterval?) {
      logExporter.shutdown(explicitTimeout: explicitTimeout)
    }

    package func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult {
      guard shouldExport() else { return .success }
      return logExporter.forceFlush(explicitTimeout: explicitTimeout)
    }
  }

  package static func defaultPersistenceStorageURL() -> URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base
      .appendingPathComponent("opentelemetry", isDirectory: true)
      .appendingPathComponent("terra", isDirectory: true)
  }

  package enum InstallOpenTelemetryError: Error {
    case alreadyInstalled
  }

  private static let openTelemetryInstallLock = NSLock()
  private static var installedOpenTelemetryConfiguration: OpenTelemetryConfiguration?
  private static var installedTracerProvider: TracerProviderSdk?
  private static var installedMeterProvider: MeterProviderSdk?
  private static var installedLogProcessor: (any LogRecordProcessor)?
  private static var ownsInstalledTracerProvider: Bool = false

  package static var _installedOpenTelemetryConfiguration: OpenTelemetryConfiguration? {
    openTelemetryInstallLock.lock()
    let value = installedOpenTelemetryConfiguration
    openTelemetryInstallLock.unlock()
    return value
  }

  package static var _hasInstalledOpenTelemetryProviders: Bool {
    openTelemetryInstallLock.lock()
    let hasProviders = installedTracerProvider != nil || installedMeterProvider != nil || installedLogProcessor != nil
    openTelemetryInstallLock.unlock()
    return hasProviders
  }

  /// Convenience for end-to-end OpenTelemetry wiring:
  /// - Traces exported via OTLP/HTTP (optionally persisted on-device).
  /// - Metrics exported via OTLP/HTTP (optionally persisted on-device).
  /// - Signposts enabled so spans appear in Instruments (when supported).
  /// - Sessions enabled so session IDs are attached to spans (optional).
  ///
  /// This configures global OpenTelemetry providers and also configures Terra's internal meter usage.
  ///
  /// - Throws: `InstallOpenTelemetryError.alreadyInstalled` if called more than once with a different configuration.
  package static func installOpenTelemetry(_ configuration: OpenTelemetryConfiguration) throws {
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
      Runtime.shared.markStarting()
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
      Runtime.shared.markStopped()
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
      let networkExporter = SimulatorAwareSpanExporter(
        spanExporter: OtlpHttpTraceExporter(endpoint: configuration.otlpTracesEndpoint)
      )
      let exporter: any SpanExporter
      if let persistence = configuration.persistence {
        try FileManager.default.createDirectory(at: persistence.tracesStorageURL, withIntermediateDirectories: true, attributes: nil)
        exporter = try PersistenceSpanExporterDecorator(
          spanExporter: networkExporter,
          storageURL: persistence.tracesStorageURL,
          performancePreset: persistence.performancePreset
        )
      } else {
        exporter = networkExporter
      }
      return exporter
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
      let networkExporter = SimulatorAwareMetricExporter(
        metricExporter: OtlpHttpMetricExporter(endpoint: configuration.otlpMetricsEndpoint)
      )
      let exporter: any MetricExporter
      if let persistence = configuration.persistence {
        try FileManager.default.createDirectory(at: persistence.metricsStorageURL, withIntermediateDirectories: true, attributes: nil)
        exporter = try PersistenceMetricExporterDecorator(
          metricExporter: networkExporter,
          storageURL: persistence.metricsStorageURL,
          performancePreset: persistence.performancePreset
        )
      } else {
        exporter = networkExporter
      }
      return exporter
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
      let networkExporter = SimulatorAwareLogExporter(
        logExporter: OtlpHttpLogExporter(endpoint: configuration.otlpLogsEndpoint)
      )
      let exporter: any LogRecordExporter
      if let persistence = configuration.persistence {
        try FileManager.default.createDirectory(at: persistence.logsStorageURL, withIntermediateDirectories: true, attributes: nil)
        exporter = try PersistenceLogExporterDecorator(
          logRecordExporter: networkExporter,
          storageURL: persistence.logsStorageURL,
          performancePreset: persistence.performancePreset
        )
      } else {
        exporter = networkExporter
      }
      return exporter
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
  package static var _lifecycleState: Terra.LifecycleState {
    Runtime.shared.lifecycleState
  }

  /// `true` when Terra has been started and is actively collecting telemetry.
  package static var _isRunning: Bool {
    _lifecycleState == .running
  }

  private static let _simulatorExportBlockedLock = NSLock()
  private static var _simulatorExportBlockedValue = false

  /// Blocks or unblocks telemetry export when running in the simulator.
  package static func _setSimulatorExportBlocked(_ blocked: Bool) {
    _simulatorExportBlockedLock.withLock { _simulatorExportBlockedValue = blocked }
  }

  /// Returns whether simulator export is currently blocked.
  package static var _isSimulatorExportBlocked: Bool {
    _simulatorExportBlockedLock.withLock { _simulatorExportBlockedValue }
  }

  // MARK: - Shutdown

  /// Shuts down Terra gracefully, resetting the runtime to `.stopped`.
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
  package static func _shutdownOpenTelemetry() {
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
    Runtime.shared.markShuttingDown()
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

    Runtime.shared.markStopped()
  }
}

#if DEBUG
extension Terra {
  // Tests can lock in one thread and unlock after an async hop on another.
  // DispatchSemaphore avoids thread-affinity lock ownership issues in that path.
  private static let testingIsolationLock = DispatchSemaphore(value: 1)

  package static func lockTestingIsolation() {
    testingIsolationLock.wait()
  }

  package static func unlockTestingIsolation() {
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
    Runtime.shared.markStopped()
  }
}
#endif
