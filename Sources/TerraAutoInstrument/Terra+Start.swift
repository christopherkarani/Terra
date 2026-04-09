import Foundation
@_exported import TerraCore
import TerraCoreML
import TerraHTTPInstrument
import TerraMetalProfiler
import TerraSystemProfiler
import OpenTelemetryApi
import OpenTelemetrySdk

extension Terra {
  /// Configuration for Terra initialization.
  ///
  /// `Configuration` groups all runtime settings for Terra — including privacy policy,
  /// telemetry destination, enabled features, persistence, and hardware profiling. Use
  /// one of the built-in `Preset` values for common setups, or configure each option
  /// individually for fine-grained control.
  ///
  /// - Note: All properties have sensible defaults via the `.quickstart` preset.
  ///   Call `Terra.start()` with no arguments for zero-config setup.
  ///
  /// - SeeAlso: `Terra.start(_:)`
  public struct Configuration: Sendable, Equatable {
    public struct ProductionIngest: Sendable, Equatable {
      public var environmentName: String
      public var ingestKey: String
      public var installationID: String?

      public init(
        environmentName: String,
        ingestKey: String,
        installationID: String? = nil
      ) {
        self.environmentName = environmentName
        self.ingestKey = ingestKey
        self.installationID = installationID
      }
    }

    /// Predefined configuration presets for common use cases.
    ///
    /// Each preset applies a specific combination of privacy, features, persistence,
    /// and profiling settings tuned for the target environment.
    public enum Preset: Sendable, Equatable {
      /// Minimal setup for local development.
      ///
      /// Privacy is set to `.redacted`, CoreML and HTTP instrumentation are enabled,
      /// and no persistence or profiling is active. Traces are sent to the local
      /// dashboard endpoint (`http://127.0.0.1:4318`).
      case quickstart

      /// Production configuration with local persistence.
      ///
      /// Privacy is set to `.redacted`, CoreML and HTTP instrumentation are enabled,
      /// signposts are disabled, and traces/metrics are persisted to disk in balanced
      /// mode (optimized for write performance). Use this for app-store builds.
      case production

      /// Diagnostics configuration with profiling enabled.
      ///
      /// All features are enabled including signposts and logs, with balanced persistence
      /// and standard hardware profiling (memory and thermal). Use this when you need
      /// detailed performance data during development or QA.
      case diagnostics
    }

    /// Where telemetry data is sent.
    public enum Destination: Sendable, Equatable {
      /// Sends telemetry to the local development dashboard (default).
      ///
      /// Points to `http://127.0.0.1:4318`, the local OpenTelemetry Collector
      /// expected by the Terra dashboard app.
      case localDashboard

      /// Sends telemetry to a custom OTLP-compatible endpoint.
      ///
      /// Use this to route telemetry to your own OpenTelemetry Collector,
      /// Grafana Tempo, or other compatible backends.
      ///
      /// - Parameter URL: A valid OTLP endpoint URL (must use `http` or `https` scheme
      ///   and include a host). Terra validates this when `Terra.start()` is called.
      case endpoint(URL)
    }

    /// Persistence settings for offline telemetry storage.
    ///
    /// When persistence is enabled, Terra stores telemetry to disk when the network
    /// is unavailable and exports it automatically when connectivity is restored.
    public enum Persistence: Sendable, Equatable {
      /// Disables persistence — telemetry is only exported when a backend is reachable.
      case off

      /// Balances write performance and export frequency for general use.
      ///
      /// Suitable for production. Writes are batched and exported every ~5 seconds,
      /// with file rotation to prevent unbounded disk usage.
      ///
      /// - Parameter URL: The directory where persistence files are stored.
      ///   Terra creates a `Terra` subdirectory within this location.
      case balanced(URL)

      /// Maximizes data durability at the cost of write throughput.
      ///
      /// Suitable when you cannot tolerate any data loss. Each export is written
      /// synchronously before returning.
      ///
      /// - Parameter URL: The directory where persistence files are stored.
      case instant(URL)
    }

    /// Hardware profiling options to collect system-level metrics alongside telemetry.
    ///
    /// Profiling data (memory pressure, GPU utilization, thermal state) is recorded as
    /// OpenTelemetry metrics on each span, enabling correlation of model performance
    /// with system resource state in dashboards.
    ///
    /// - Note: `.power` and `.ane` require opt-in targets (`TerraPowerProfiler`,
    ///   `TerraANEProfiler`) that are not dependencies of the Terra umbrella.
    ///   The flag values are reserved so downstream wrappers can read and act on them.
    public struct Profiling: OptionSet, Sendable, Hashable {
      public let rawValue: Int
      public init(rawValue: Int) { self.rawValue = rawValue }

      /// Records system memory pressure and allocation metrics.
      public static let memory   = Profiling(rawValue: 1 << 0)

      /// Records Metal GPU utilization and memory metrics for CoreML model execution.
      public static let metal    = Profiling(rawValue: 1 << 1)

      /// Records the device thermal state (nominal/fair/serious/critical).
      public static let thermal  = Profiling(rawValue: 1 << 2)

      /// Records battery power and energy consumption metrics (macOS only).
      public static let power    = Profiling(rawValue: 1 << 3)

      /// Records CPU frequency and performance state metrics (macOS only).
      public static let espresso = Profiling(rawValue: 1 << 4)

      /// Records Apple Neural Engine (ANE) utilization via private APIs.
      ///
      /// - Warning: Uses private APIs (`ANEDeviceMonitor`). Not suitable for App Store
      ///   distribution. Import `TerraANEProfiler` and install it directly if needed.
      public static let ane      = Profiling(rawValue: 1 << 5)

      /// Progressive disclosure tier: memory + thermal profiling.
      ///
      /// Good balance of insight with minimal overhead. Suitable for most diagnostic scenarios.
      public static let standard: Profiling = [.memory, .thermal]

      /// Extended profiling: memory, thermal, Metal, and power.
      ///
      /// Provides comprehensive hardware visibility for detailed performance investigations.
      public static let extended: Profiling = [.memory, .thermal, .metal, .power]

      /// All profiling features enabled.
      ///
      /// Maximum data collection. May have meaningful performance overhead.
      public static let all: Profiling      = [.memory, .thermal, .metal, .power, .espresso, .ane]
    }

    /// Feature flags enabling specific Terra instrumentation modules.
    public struct Features: OptionSet, Sendable, Equatable {
      public let rawValue: Int
      public init(rawValue: Int) { self.rawValue = rawValue }

      /// Auto-instrument CoreML `MLModel.prediction(from:)` calls.
      ///
      /// Traces all CoreML model invocations with input/output shapes, latency,
      /// and hardware routing (CPU/GPU/ANE).
      public static let coreML    = Features(rawValue: 1 << 0)

      /// Auto-instrument HTTP requests to known AI API endpoints (OpenAI, Anthropic, Google, etc.).
      public static let http      = Features(rawValue: 1 << 1)

      /// Enable session-level correlation IDs for grouping traces by user session.
      public static let sessions  = Features(rawValue: 1 << 2)

      /// Record OS Signpost intervals for fine-grained performance profiling in Instruments.
      public static let signposts = Features(rawValue: 1 << 3)

      /// Export structured diagnostic logs via OpenClaw.
      ///
      /// When enabled, Terra exports diagnostic logs (startup, shutdown, configuration)
      /// to the OTLP logs endpoint. Requires `destination` to point to an OTLP-compatible backend.
      public static let logs      = Features(rawValue: 1 << 4)
    }

    /// The privacy policy controlling how content (prompts, responses) is handled in traces.
    ///
    /// Defaults to `.redacted`, which strips content from spans and only records metadata
    /// (model IDs, token counts, latency). Set to `.capturing` to include raw content when
    /// the calling code opts in via `Operation.capture(.includeContent)`.
    public var privacy: Terra.PrivacyPolicy

    /// The destination for telemetry export.
    ///
    /// Defaults to `.localDashboard` which routes to `http://127.0.0.1:4318`
    /// (the local OpenTelemetry Collector). Change to `.endpoint` to export to
    /// your own OTLP-compatible backend.
    public var destination: Destination

    /// The set of instrumentation features enabled.
    ///
    /// Each feature corresponds to a specific auto-instrumentation module.
    /// For example, `.coreML` enables CoreML call tracing and `.http` enables
    /// AI API HTTP request tracing. Combine multiple features with `.union`.
    public var features: Features

    /// Persistence configuration for offline storage and retry on network failure.
    ///
    /// When set to `.off` (default in quickstart), telemetry is only exported when
    /// the network is available. Enable persistence to survive network outages and
    /// ensure no data is lost.
    public var persistence: Persistence

    /// Hardware profiling options for system-level metrics collection.
    ///
    /// Each option enables recording of specific system metrics (memory, GPU, thermal)
    /// alongside telemetry spans, making it possible to correlate model performance
    /// with hardware state in dashboards.
    public var profiling: Profiling

    /// Optional production OTLP ingest configuration.
    ///
    /// When set, Terra adds the bearer auth header required by the hosted
    /// control plane and stamps the resource identity fields expected by the
    /// production ingest contract.
    public var productionIngest: ProductionIngest?

    /// Creates a configuration from a preset, or the `.quickstart` preset by default.
    ///
    /// - Parameter preset: One of `.quickstart`, `.production`, or `.diagnostics`.
    public init(preset: Preset = .quickstart) {
      switch preset {
      case .quickstart:
        privacy = .redacted
        destination = .localDashboard
        features = [.coreML, .http, .sessions, .signposts]
        persistence = .off
        profiling = []
        productionIngest = nil
      case .production:
        privacy = .redacted
        destination = .localDashboard
        features = [.coreML, .http, .sessions]
        persistence = .balanced(Terra.defaultPersistenceStorageURL())
        profiling = []
        productionIngest = nil
      case .diagnostics:
        privacy = .redacted
        destination = .localDashboard
        features = [.coreML, .http, .sessions, .signposts, .logs]
        persistence = .balanced(Terra.defaultPersistenceStorageURL())
        profiling = .standard
        productionIngest = nil
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
        enableMemoryProfiler: profiling.contains(.memory),
        enableMetalProfiler: profiling.contains(.metal),
        enableThermalMonitor: profiling.contains(.thermal),
        enablePowerProfiler: profiling.contains(.power),
        enableEspressoCapture: profiling.contains(.espresso),
        enableANEProfiler: profiling.contains(.ane)
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
          otlpHeaders: [:],
          serviceName: nil,
          serviceVersion: nil,
          resourceAttributes: [:],
          traceSamplingRatio: nil
        ),
        productionIngest: productionIngest,
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

  /// Starts Terra with local-development defaults that are explicit and easy to teach.
  ///
  /// Use `quickStart()` when you want one obvious "make it work on this machine"
  /// entry point for coding agents and developers. This keeps the older `start()`
  /// defaults intact while giving local workflows a stronger, copy-pasteable setup:
  /// localhost OTLP export and `.capturing` privacy.
  ///
  /// ```swift
  /// try await Terra.quickStart()
  /// let report = Terra.diagnose()
  /// print(report.isHealthy)
  /// ```
  public static func quickStart() async throws {
    var config = Configuration(preset: .quickstart)
    config.privacy = .capturing
    config.profiling = [.memory, .thermal, .metal]
    config.destination = .endpoint(URL(string: "http://localhost:4318")!)
    try await start(config)
  }

  static func _performStart(_ config: _ResolvedStartConfiguration) throws {
    let bundleInfo = Bundle.main.infoDictionary ?? [:]
    let bundleIdentifier = Bundle.main.bundleIdentifier
    let processName = ProcessInfo.processInfo.processName
    let openTelemetryConfig = _resolveOpenTelemetryConfiguration(
      config.openTelemetry,
      productionIngest: config.productionIngest,
      bundleIdentifier: bundleIdentifier,
      bundleShortVersion: bundleInfo["CFBundleShortVersionString"] as? String,
      bundleBuild: bundleInfo["CFBundleVersion"] as? String,
      processName: processName
    )
    let serviceName = openTelemetryConfig.serviceName
    let serviceVersion = openTelemetryConfig.serviceVersion

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
    if config.profiling.enableThermalMonitor {
      ThermalMonitor.install()
    }
    // Note: .power and .ane profilers require opt-in targets (TerraPowerProfiler,
    // TerraANEProfiler) that are not dependencies of the Terra umbrella. Users
    // wanting those profilers import and install them directly. The settings flags
    // are reserved so downstream wrappers can read and act on them.
    #if os(macOS)
    if config.profiling.enableEspressoCapture {
      EspressoLogCapture.start()
    }
    #endif

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

  package static var _defaultPlatformIdentifier: String {
    #if os(iOS)
      return "ios"
    #elseif os(macOS)
      return "macos"
    #elseif os(tvOS)
      return "tvos"
    #elseif os(watchOS)
      return "watchos"
    #elseif os(visionOS)
      return "visionos"
    #else
      return "unknown"
    #endif
  }

  package static func _resolveOpenTelemetryConfiguration(
    _ configuration: OpenTelemetryConfiguration,
    productionIngest: Configuration.ProductionIngest?,
    bundleIdentifier: String?,
    bundleShortVersion: String?,
    bundleBuild: String?,
    processName: String
  ) -> OpenTelemetryConfiguration {
    var resolved = configuration
    let serviceName = resolved.serviceName
      ?? bundleIdentifier
      ?? processName
    let serviceVersion = resolved.serviceVersion
      ?? bundleShortVersion

    resolved.serviceName = serviceName
    resolved.serviceVersion = serviceVersion

    guard let productionIngest else {
      return resolved
    }

    let installationID = Terra.resolveInstallationIdentity(
      explicit: productionIngest.installationID,
      namespace: bundleIdentifier ?? serviceName
    )
    let appIdentifier = bundleIdentifier ?? serviceName
    let appVersion = serviceVersion ?? bundleBuild ?? "0.0.0"

    resolved.otlpHeaders["Authorization"] = "Bearer \(productionIngest.ingestKey)"
    resolved.resourceAttributes["terra.installation.id"] = .string(installationID)
    resolved.resourceAttributes["service.instance.id"] = .string(installationID)
    resolved.resourceAttributes["terra.platform"] = .string(_defaultPlatformIdentifier)
    resolved.resourceAttributes["deployment.environment.name"] = .string(productionIngest.environmentName)
    resolved.resourceAttributes["deployment.environment"] = .string(productionIngest.environmentName)
    resolved.resourceAttributes["terra.app.identifier"] = .string(appIdentifier)
    resolved.resourceAttributes["terra.app.version"] = .string(appVersion)
    if let bundleIdentifier {
      resolved.resourceAttributes["terra.app.bundle_id"] = .string(bundleIdentifier)
    }
    if let bundleBuild, !bundleBuild.isEmpty {
      resolved.resourceAttributes["terra.app.build"] = .string(bundleBuild)
    }
    return resolved
  }
}

// MARK: - Internal types (package-scoped)

extension Terra {
  package struct _ProfilingSettings: Sendable, Equatable {
    package var enableMemoryProfiler: Bool
    package var enableMetalProfiler: Bool
    package var enableThermalMonitor: Bool
    package var enablePowerProfiler: Bool
    package var enableEspressoCapture: Bool
    package var enableANEProfiler: Bool

    package init(
      enableMemoryProfiler: Bool = false,
      enableMetalProfiler: Bool = false,
      enableThermalMonitor: Bool = false,
      enablePowerProfiler: Bool = false,
      enableEspressoCapture: Bool = false,
      enableANEProfiler: Bool = false
    ) {
      self.enableMemoryProfiler = enableMemoryProfiler
      self.enableMetalProfiler = enableMetalProfiler
      self.enableThermalMonitor = enableThermalMonitor
      self.enablePowerProfiler = enablePowerProfiler
      self.enableEspressoCapture = enableEspressoCapture
      self.enableANEProfiler = enableANEProfiler
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
    var productionIngest: Configuration.ProductionIngest?
    var instrumentations: _Instrumentations
    var openClaw: OpenClawConfiguration
    var proxy: ProxyConfiguration?
    var aiAPIHosts: Set<String>
    var excludedCoreMLModels: Set<String>
    var profiling: _ProfilingSettings
  }
}
