import Foundation
@_exported import TerraCore
import TerraCoreML
import TerraHTTPInstrument
import TerraMetalProfiler
import TerraSystemProfiler
import OpenTelemetryApi
import OpenTelemetrySdk

extension Terra {
  public struct Configuration: Sendable, Equatable {

    public enum Preset: Sendable, Equatable {
      case quickstart
      case production
      case diagnostics
    }

    public enum Destination: Sendable, Equatable {
      case localDashboard
      case endpoint(URL)
    }

    public enum Persistence: Sendable, Equatable {
      case off
      case balanced(URL)
      case instant(URL)
    }

    public enum Profiling: Sendable, Equatable {
      case off
      case memory
      case metal
      case all
    }

    public struct Features: OptionSet, Sendable, Equatable {
      public let rawValue: Int
      public init(rawValue: Int) { self.rawValue = rawValue }
      public static let coreML    = Features(rawValue: 1 << 0)
      public static let http      = Features(rawValue: 1 << 1)
      public static let sessions  = Features(rawValue: 1 << 2)
      public static let signposts = Features(rawValue: 1 << 3)
      public static let logs      = Features(rawValue: 1 << 4)
    }

    public var privacy: Terra.PrivacyPolicy
    public var destination: Destination
    public var features: Features
    public var persistence: Persistence
    public var profiling: Profiling

    public init(preset: Preset = .quickstart) {
      switch preset {
      case .quickstart:
        privacy = .redacted
        destination = .localDashboard
        features = [.coreML, .http, .sessions, .signposts]
        persistence = .off
        profiling = .off
      case .production:
        privacy = .redacted
        destination = .localDashboard
        features = [.coreML, .http, .sessions]
        persistence = .balanced(Terra.defaultPersistenceStorageURL())
        profiling = .off
      case .diagnostics:
        privacy = .redacted
        destination = .localDashboard
        features = [.coreML, .http, .sessions, .signposts, .logs]
        persistence = .balanced(Terra.defaultPersistenceStorageURL())
        profiling = .all
      }
    }

    func asAutoInstrumentConfiguration() -> _ResolvedStartConfiguration {
      // derive endpoint URL from destination
      let endpointURL: URL
      switch destination {
      case .localDashboard:
        endpointURL = URL(string: "http://127.0.0.1:4318")!
      case .endpoint(let url):
        endpointURL = url
      }

      // derive persistence config
      let persistenceConfig: _PersistenceSettings?
      switch persistence {
      case .off:
        persistenceConfig = nil
      case .balanced(let url):
        persistenceConfig = .init(storageURL: url, performance: .balanced)
      case .instant(let url):
        persistenceConfig = .init(storageURL: url, performance: .instantDelivery)
      }

      // derive profiling
      let profilingSettings = _ProfilingSettings(
        enableMemoryProfiler: profiling == .memory || profiling == .all,
        enableMetalProfiler: profiling == .metal || profiling == .all
      )

      // derive instrumentations
      var instrumentations = _Instrumentations.none
      if features.contains(.coreML) { instrumentations.insert(.coreML) }
      if features.contains(.http) { instrumentations.insert(.httpAIAPIs) }

      // derive openClaw — diagnostics preset enables diagnostics export
      let openClawConfig: OpenClawConfiguration = features.contains(.logs)
        ? .init(mode: .diagnosticsOnly)
        : .disabled

      return .init(
        privacy: .init(
          contentPolicy: {
            switch privacy {
            case .capturing: return .always
            case .silent: return .never
            case .redacted, .lengthOnly: return .optIn
            }
          }(),
          redaction: privacy.redactionStrategy,
          anonymizationKey: nil
        ),
        openTelemetry: .init(
          enableTraces: true,
          enableMetrics: true,
          enableLogs: features.contains(.logs),
          enableSignposts: features.contains(.signposts),
          enableSessions: features.contains(.sessions),
          otlpTracesEndpoint: endpointURL.appendingPathComponent("v1/traces"),
          otlpMetricsEndpoint: endpointURL.appendingPathComponent("v1/metrics"),
          otlpLogsEndpoint: endpointURL.appendingPathComponent("v1/logs"),
          metricsExportInterval: features.contains(.logs) ? 15 : 60,
          persistence: persistenceConfig.map(\.asInternalConfiguration),
          serviceName: nil,
          serviceVersion: nil,
          resourceAttributes: [:],
          traceSamplingRatio: nil
        ),
        instrumentations: instrumentations,
        openClaw: openClawConfig,
        proxy: nil,
        aiAPIHosts: HTTPAIInstrumentation.defaultAIHosts,
        excludedCoreMLModels: [],
        profiling: profilingSettings
      )
    }
  }

  /// Start Terra telemetry with a configuration value.
  ///
  /// This is the canonical entry point. Pass a `Configuration` to customize
  /// behavior, or call with no arguments for quickstart defaults.
  ///
  /// ```swift
  /// // Quickstart (zero config)
  /// try await Terra.start()
  ///
  /// // Production with persistence
  /// try await Terra.start(.init(preset: .production))
  ///
  /// // Diagnostics
  /// try await Terra.start(.init(preset: .diagnostics))
  /// ```
  ///
  /// - Throws: `TerraError` with deterministic codes such as
  ///   `.invalid_endpoint`, `.persistence_setup_failed`, `.already_started`,
  ///   or `.invalid_lifecycle_state`.
  public static func start(_ config: Configuration = .init()) async throws {
    try await _lifecycleController.start(config)
  }

  static func _performStart(_ config: _ResolvedStartConfiguration) throws {
    // 0. Resolve service metadata
    let serviceName = config.openTelemetry.serviceName
      ?? Bundle.main.bundleIdentifier
      ?? ProcessInfo.processInfo.processName
    let serviceVersion = config.openTelemetry.serviceVersion
      ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    var openTelemetryConfig = config.openTelemetry
    openTelemetryConfig.serviceName = serviceName
    openTelemetryConfig.serviceVersion = serviceVersion

    // 1. Set up telemetry providers.
    // Use the Zig tracer path only when the resolved configuration can be
    // honored there without silently dropping lifecycle or persistence behavior.
    #if canImport(CTerraBridge)
    if _supportsZigBackend(openTelemetryConfig) {
      let zigInstalled = installZigBackend(
        serviceName: serviceName,
        serviceVersion: serviceVersion
      )
      if !zigInstalled {
        try installOpenTelemetry(openTelemetryConfig)
      }
    } else {
      try installOpenTelemetry(openTelemetryConfig)
    }
    #else
    try installOpenTelemetry(openTelemetryConfig)
    #endif

    // 2. Install Terra runtime (privacy, providers)
    install(.init(privacy: config.privacy))

    // 3. Enable CoreML auto-instrumentation
    CoreMLInstrumentation.install(.init(
      enabled: config.instrumentations.contains(.coreML),
      excludedModels: config.excludedCoreMLModels
    ))

    // 3b. Optional low-level profilers.
    if config.profiling.enableMemoryProfiler {
      TerraSystemProfiler.install()
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
        hosts: config.instrumentations.contains(.httpAIAPIs) ? monitoredHosts : [],
        openClawGatewayHosts: openClawGatewayHosts,
        openClawMode: config.openClaw.modeString
      )
    } else {
      HTTPAIInstrumentation.install(
        hosts: [],
        openClawGatewayHosts: [],
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
    OpenClawDiagnosticsExporter.configure(configuration: shouldEnableDiagnostics ? config.openClaw : .disabled)
  }

  static func _disableAutoInstrumentationsForShutdown() {
    CoreMLInstrumentation.install(.init(enabled: false, excludedModels: []))
    HTTPAIInstrumentation.install(hosts: [], openClawGatewayHosts: [], openClawMode: "disabled")
    OpenClawDiagnosticsExporter.configure(configuration: .disabled)
  }

  /// Returns the minimal `Features` set used by TerraSession for auto-start.
  package static func _minimalFeatures() -> Configuration.Features {
    [.coreML]
  }
}

// MARK: - Internal types (package-scoped)

extension Terra {
  package struct _ProfilingSettings: Sendable, Equatable {
    package var enableMemoryProfiler: Bool
    package var enableMetalProfiler: Bool

    package init(
      enableMemoryProfiler: Bool = false,
      enableMetalProfiler: Bool = false
    ) {
      self.enableMemoryProfiler = enableMemoryProfiler
      self.enableMetalProfiler = enableMetalProfiler
    }
  }

  /// Which auto-instrumentations to enable with `Terra.start()`.
  package struct _Instrumentations: OptionSet, Sendable, Equatable {
    package let rawValue: Int
    package init(rawValue: Int) { self.rawValue = rawValue }

    /// Auto-instrument CoreML `MLModel.prediction(from:)` calls.
    package static let coreML = _Instrumentations(rawValue: 1 << 0)

    /// Auto-instrument HTTP requests to known AI API endpoints.
    package static let httpAIAPIs = _Instrumentations(rawValue: 1 << 1)

    /// Reserved for low-level proxy instrumentation.
    package static let proxy = _Instrumentations(rawValue: 1 << 2)

    /// Auto-instrument OpenClaw gateway requests (localhost/OpenClaw hosts).
    package static let openClawGateway = _Instrumentations(rawValue: 1 << 3)

    /// Reserve OpenClaw diagnostics mode so SDK config matches dashboard capabilities.
    package static let openClawDiagnostics = _Instrumentations(rawValue: 1 << 4)

    /// Enable default auto-instrumentations.
    package static let all: _Instrumentations = [.coreML, .httpAIAPIs]

    /// Disable all auto-instrumentations (useful for custom setups).
    package static let none = _Instrumentations([])
  }

  package struct _PersistenceSettings: Equatable, Sendable {
    package struct Performance: Equatable, Sendable {
      package var maxFileSize: UInt64
      package var maxDirectorySize: UInt64
      package var maxFileAgeForWrite: TimeInterval
      package var minFileAgeForRead: TimeInterval
      package var maxFileAgeForRead: TimeInterval
      package var maxObjectsInFile: Int
      package var maxObjectSize: UInt64
      package var synchronousWrite: Bool

      package var initialExportDelay: TimeInterval
      package var defaultExportDelay: TimeInterval
      package var minExportDelay: TimeInterval
      package var maxExportDelay: TimeInterval
      package var exportDelayChangeRate: Double

      package init(
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

      package static let balanced = Performance(
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

      package static let instantDelivery = Performance(
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

    package var storageURL: URL
    package var performance: Performance

    package init(
      storageURL: URL,
      performance: Performance = .balanced
    ) {
      self.storageURL = storageURL
      self.performance = performance
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
  }
}

extension Terra {
  private static func _supportsZigBackend(_ configuration: OpenTelemetryConfiguration) -> Bool {
    configuration.tracerProviderStrategy == .registerNew
      && configuration.enableTraces
      && !configuration.enableMetrics
      && !configuration.enableLogs
      && !configuration.enableSignposts
      && !configuration.enableSessions
      && configuration.persistence == nil
      && configuration.traceSamplingRatio == nil
  }

  struct _ResolvedStartConfiguration: Sendable {
    var privacy: Privacy
    var openTelemetry: OpenTelemetryConfiguration
    var instrumentations: _Instrumentations
    var openClaw: OpenClawConfiguration
    var proxy: ProxyConfiguration?
    var aiAPIHosts: Set<String>
    var excludedCoreMLModels: Set<String>
    var profiling: _ProfilingSettings
  }
}
