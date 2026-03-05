import Foundation
@_exported import TerraCore
import TerraCoreML
import TerraHTTPInstrument
import TerraMetalProfiler
import TerraSystemProfiler
import OpenTelemetryApi
import OpenTelemetrySdk

extension Terra {
  public struct Configuration: Sendable {
    public enum Preset: Sendable {
      case quickstart
      case production
      case diagnostics
    }

    public var privacy: Terra.PrivacyPolicy = .redacted
    public var endpoint: URL = .init(string: "http://127.0.0.1:4318")!
    public var serviceName: String? = nil
    public var instrumentations: Instrumentations = .all
    public var serviceVersion: String? = nil
    public var anonymizationKey: Data? = nil
    public var samplingRatio: Double? = nil
    public var persistence: Persistence? = nil
    public var metricsInterval: TimeInterval = 60
    public var enableSignposts: Bool = true
    public var enableSessions: Bool = true
    public var resourceAttributes: [String: String] = [:]
    public var profiling: Profiling = .init()
    public var openClaw: OpenClawConfiguration = .disabled
    public var excludedCoreMLModels: Set<String> = []
    public var enableLogs: Bool = false

    public init() {}

    public init(preset: Preset = .quickstart) {
      self.init()
      switch preset {
      case .quickstart:
        break
      case .production:
        persistence = .init(
          storageURL: Terra.defaultPersistenceStorageURL(),
          performance: .balanced
        )
      case .diagnostics:
        persistence = .init(
          storageURL: Terra.defaultPersistenceStorageURL(),
          performance: .balanced
        )
        instrumentations.insert(.openClawDiagnostics)
        enableSignposts = true
        enableSessions = true
        enableLogs = true
        metricsInterval = 15
        profiling = .init(enableMemoryProfiler: true, enableMetalProfiler: true)
        openClaw = .init(mode: .diagnosticsOnly)
        resourceAttributes["terra.profile"] = "diagnostics"
      }
    }

    func asAutoInstrumentConfiguration() -> _ResolvedStartConfiguration {
      var openTelemetryAttributes: [String: AttributeValue] = [:]
      for (key, value) in resourceAttributes {
        openTelemetryAttributes[key] = .string(value)
      }
      return .init(
        privacy: .init(
          contentPolicy: {
            switch privacy {
            case .capturing:
              return .always
            case .silent:
              return .never
            case .redacted, .lengthOnly:
              return .optIn
            }
          }(),
          redaction: privacy.redactionStrategy,
          anonymizationKey: anonymizationKey
        ),
        openTelemetry: .init(
          enableTraces: true,
          enableMetrics: true,
          enableLogs: enableLogs,
          enableSignposts: enableSignposts,
          enableSessions: enableSessions,
          otlpTracesEndpoint: endpoint.appendingPathComponent("v1/traces"),
          otlpMetricsEndpoint: endpoint.appendingPathComponent("v1/metrics"),
          otlpLogsEndpoint: endpoint.appendingPathComponent("v1/logs"),
          metricsExportInterval: metricsInterval,
          persistence: persistence.map(\.asInternalConfiguration),
          serviceName: serviceName,
          serviceVersion: serviceVersion,
          resourceAttributes: openTelemetryAttributes,
          traceSamplingRatio: samplingRatio
        ),
        instrumentations: instrumentations,
        openClaw: openClaw,
        proxy: nil,
        aiAPIHosts: HTTPAIInstrumentation.defaultAIHosts,
        excludedCoreMLModels: excludedCoreMLModels,
        profiling: profiling
      )
    }

    public struct Persistence: Equatable, Sendable {
      public struct Performance: Equatable, Sendable {
        public var maxFileSize: UInt64
        public var maxDirectorySize: UInt64
        public var maxFileAgeForWrite: TimeInterval
        public var minFileAgeForRead: TimeInterval
        public var maxFileAgeForRead: TimeInterval
        public var maxObjectsInFile: Int
        public var maxObjectSize: UInt64
        public var synchronousWrite: Bool

        public var initialExportDelay: TimeInterval
        public var defaultExportDelay: TimeInterval
        public var minExportDelay: TimeInterval
        public var maxExportDelay: TimeInterval
        public var exportDelayChangeRate: Double

        public init(
          maxFileSize: UInt64,
          maxDirectorySize: UInt64,
          maxFileAgeForWrite: TimeInterval,
          minFileAgeForRead: TimeInterval,
          maxFileAgeForRead: TimeInterval,
          maxObjectsInFile: Int,
          maxObjectSize: UInt64,
          synchronousWrite: Bool,
          initialExportDelay: TimeInterval,
          defaultExportDelay: TimeInterval,
          minExportDelay: TimeInterval,
          maxExportDelay: TimeInterval,
          exportDelayChangeRate: Double
        ) {
          self.maxFileSize = maxFileSize
          self.maxDirectorySize = maxDirectorySize
          self.maxFileAgeForWrite = maxFileAgeForWrite
          self.minFileAgeForRead = minFileAgeForRead
          self.maxFileAgeForRead = maxFileAgeForRead
          self.maxObjectsInFile = maxObjectsInFile
          self.maxObjectSize = maxObjectSize
          self.synchronousWrite = synchronousWrite
          self.initialExportDelay = initialExportDelay
          self.defaultExportDelay = defaultExportDelay
          self.minExportDelay = minExportDelay
          self.maxExportDelay = maxExportDelay
          self.exportDelayChangeRate = exportDelayChangeRate
        }

        public static let balanced = Performance(
          maxFileSize: 4 * 1_024 * 1_024,
          maxDirectorySize: 512 * 1_024 * 1_024,
          maxFileAgeForWrite: 4.75,
          minFileAgeForRead: 5.25,
          maxFileAgeForRead: 18 * 60 * 60,
          maxObjectsInFile: 500,
          maxObjectSize: 256 * 1_024,
          synchronousWrite: false,
          initialExportDelay: 5,
          defaultExportDelay: 5,
          minExportDelay: 1,
          maxExportDelay: 20,
          exportDelayChangeRate: 0.1
        )

        public static let lowRuntimeImpact = balanced

        public static let instantDelivery = Performance(
          maxFileSize: 4 * 1_024 * 1_024,
          maxDirectorySize: 512 * 1_024 * 1_024,
          maxFileAgeForWrite: 2.75,
          minFileAgeForRead: 3.25,
          maxFileAgeForRead: 18 * 60 * 60,
          maxObjectsInFile: 500,
          maxObjectSize: 256 * 1_024,
          synchronousWrite: true,
          initialExportDelay: 0.5,
          defaultExportDelay: 3,
          minExportDelay: 1,
          maxExportDelay: 5,
          exportDelayChangeRate: 0.5
        )
      }

      public var storageURL: URL
      public var performance: Performance

      public init(
        storageURL: URL,
        performance: Performance = .balanced
      ) {
        self.storageURL = storageURL
        self.performance = performance
      }

      public static func defaults() -> Self {
        .init(storageURL: defaultStorageURL(), performance: .balanced)
      }

      public static func defaults(storageURL: URL) -> Self {
        .init(storageURL: storageURL, performance: .balanced)
      }

      fileprivate var asInternalConfiguration: PersistenceConfiguration {
        .init(
          storageURL: storageURL,
          performancePreset: .init(
            maxFileSize: performance.maxFileSize,
            maxDirectorySize: performance.maxDirectorySize,
            maxFileAgeForWrite: performance.maxFileAgeForWrite,
            minFileAgeForRead: performance.minFileAgeForRead,
            maxFileAgeForRead: performance.maxFileAgeForRead,
            maxObjectsInFile: performance.maxObjectsInFile,
            maxObjectSize: performance.maxObjectSize,
            synchronousWrite: performance.synchronousWrite,
            initialExportDelay: performance.initialExportDelay,
            defaultExportDelay: performance.defaultExportDelay,
            minExportDelay: performance.minExportDelay,
            maxExportDelay: performance.maxExportDelay,
            exportDelayChangeRate: performance.exportDelayChangeRate
          )
        )
      }

      private static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
          ?? FileManager.default.temporaryDirectory
        return base
          .appendingPathComponent("opentelemetry", isDirectory: true)
          .appendingPathComponent("terra", isDirectory: true)
      }
    }
  }

  public struct Profiling: Sendable {
    public var enableMemoryProfiler: Bool
    public var enableMetalProfiler: Bool

    public init(
      enableMemoryProfiler: Bool = false,
      enableMetalProfiler: Bool = false
    ) {
      self.enableMemoryProfiler = enableMemoryProfiler
      self.enableMetalProfiler = enableMetalProfiler
    }
  }

  /// Which auto-instrumentations to enable with `Terra.start()`.
  public struct Instrumentations: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Auto-instrument CoreML `MLModel.prediction(from:)` calls.
    public static let coreML = Instrumentations(rawValue: 1 << 0)

    /// Auto-instrument HTTP requests to known AI API endpoints.
    public static let httpAIAPIs = Instrumentations(rawValue: 1 << 1)

    /// Reserved for low-level proxy instrumentation.
    @available(*, deprecated, message: "Proxy instrumentation is not implemented. This option will be removed in a future release.")
    public static let proxy = Instrumentations(rawValue: 1 << 2)

    /// Auto-instrument OpenClaw gateway requests (localhost/OpenClaw hosts).
    public static let openClawGateway = Instrumentations(rawValue: 1 << 3)

    /// Reserve OpenClaw diagnostics mode so SDK config matches dashboard capabilities.
    public static let openClawDiagnostics = Instrumentations(rawValue: 1 << 4)

    /// Enable default auto-instrumentations.
    ///
    /// OpenClaw gateway/diagnostics paths remain opt-in via explicit options or OpenClaw mode.
    public static let all: Instrumentations = [.coreML, .httpAIAPIs]

    /// Disable all auto-instrumentations (useful for custom setups).
    public static let none = Instrumentations([])
  }

  /// Start Terra telemetry with a configuration value.
  ///
  /// This is the canonical entry point. Pass a `Configuration` to customize
  /// behavior, or call with no arguments for quickstart defaults.
  ///
  /// ```swift
  /// // Quickstart (zero config)
  /// try Terra.start()
  ///
  /// // Production with persistence
  /// try Terra.start(.init(preset: .production))
  ///
  /// // Custom
  /// var config = Terra.Configuration()
  /// config.enableLogs = true
  /// config.profiling.enableMemoryProfiler = true
  /// try Terra.start(config)
  /// ```
  public static func start(_ config: Configuration = .init()) throws {
    try start(config.asAutoInstrumentConfiguration())
  }

  static func start(_ config: _ResolvedStartConfiguration) throws {
    // 1. Set up OpenTelemetry providers (traces, metrics, signposts, sessions)
    var openTelemetryConfig = config.openTelemetry
    if openTelemetryConfig.serviceName == nil {
      openTelemetryConfig.serviceName = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
    }
    if openTelemetryConfig.serviceVersion == nil {
      openTelemetryConfig.serviceVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
    try installOpenTelemetry(openTelemetryConfig)

    // 2. Install Terra runtime (privacy, providers)
    install(.init(privacy: config.privacy))

    // 3. Enable CoreML auto-instrumentation
    if config.instrumentations.contains(.coreML) {
      CoreMLInstrumentation.install(.init(
        excludedModels: config.excludedCoreMLModels
      ))
    }

    // 3b. Optional low-level profilers.
    if config.profiling.enableMemoryProfiler {
      TerraSystemProfiler.installMemoryProfiler()
    }
    if config.profiling.enableMetalProfiler {
      TerraMetalProfiler.install()
    }

    // 4. Enable HTTP AI API auto-instrumentation (and optional OpenClaw gateway coverage)
    var monitoredHosts = config.aiAPIHosts
    let shouldEnableOpenClawGateway =
      config.instrumentations.contains(.openClawGateway)
      || config.openClaw.shouldEnableGatewayInstrumentation
    let openClawGatewayHosts = shouldEnableOpenClawGateway ? config.openClaw.gatewayHosts : []
    if shouldEnableOpenClawGateway {
      monitoredHosts.formUnion(openClawGatewayHosts)
    }

    if config.instrumentations.contains(.httpAIAPIs) || shouldEnableOpenClawGateway {
      HTTPAIInstrumentation.install(
        hosts: monitoredHosts,
        openClawGatewayHosts: openClawGatewayHosts,
        openClawMode: config.openClaw.modeString
      )
    }

    // 5. Preserve config-level intent for proxy instrumentation.
    if config.instrumentations.contains(.proxy), config.proxy == nil {
      assertionFailure("Proxy instrumentation requested but no proxy configuration was supplied.")
    }

    // 6. Optional OpenClaw diagnostics export mode.
    let shouldEnableDiagnostics =
      config.instrumentations.contains(.openClawDiagnostics)
      || config.openClaw.shouldEnableDiagnosticsExport
    if shouldEnableDiagnostics {
      OpenClawDiagnosticsExporter.installIfNeeded(configuration: config.openClaw)
    }
  }
}

extension Terra {
  struct _ResolvedStartConfiguration: Sendable {
    var privacy: Privacy
    var openTelemetry: OpenTelemetryConfiguration
    var instrumentations: Instrumentations
    var openClaw: OpenClawConfiguration
    var proxy: ProxyConfiguration?
    var aiAPIHosts: Set<String>
    var excludedCoreMLModels: Set<String>
    var profiling: Profiling
  }
}
