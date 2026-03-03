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
    public var persistence: PersistenceConfiguration? = nil
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
          performancePreset: .default
        )
      case .diagnostics:
        persistence = .init(
          storageURL: Terra.defaultPersistenceStorageURL(),
          performancePreset: .default
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

    public func asAutoInstrumentConfiguration() -> AutoInstrumentConfiguration {
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
          persistence: persistence,
          serviceName: serviceName,
          serviceVersion: serviceVersion,
          resourceAttributes: openTelemetryAttributes,
          traceSamplingRatio: samplingRatio
        ),
        instrumentations: instrumentations,
        openClaw: openClaw,
        excludedCoreMLModels: excludedCoreMLModels,
        profiling: profiling
      )
    }
  }

  @available(*, deprecated, renamed: "Configuration")
  public typealias V3Configuration = Configuration

  @available(*, deprecated, message: "Use Terra.start(_:configure:) or Terra.start(_:) with Terra.Configuration.")
  public static func enable(_ profile: StartProfile = .quickstart) async throws {
    try start(profile)
  }

  @available(*, deprecated, message: "Use Terra.start(_:configure:) or Terra.start(_:) with Terra.Configuration.")
  public static func configure(_ configuration: AutoInstrumentConfiguration) async throws {
    try start(configuration)
  }

  /// Configuration for `Terra.start()` auto-instrumentation.
  @available(*, deprecated, message: "Use Terra.Configuration instead.")
  public struct AutoInstrumentConfiguration: Sendable {
    /// Privacy settings for all auto-instrumented spans.
    public var privacy: Privacy

    /// OpenTelemetry configuration (endpoints, persistence, etc.).
    public var openTelemetry: OpenTelemetryConfiguration

    /// Which auto-instrumentations to enable.
    public var instrumentations: Instrumentations

    /// OpenClaw-specific configuration for diagnostics and gateway paths.
    public var openClaw: OpenClawConfiguration

    /// Optional proxy configuration used when `.proxy` instrumentation is enabled.
    public var proxy: ProxyConfiguration?

    /// Known AI API hosts for HTTP instrumentation.
    public var aiAPIHosts: Set<String>

    /// Model names to exclude from CoreML auto-instrumentation.
    public var excludedCoreMLModels: Set<String>

    /// Low-level profiling toggles (memory/GPU).
    public var profiling: Profiling

    public init(
      privacy: Privacy = .default,
      openTelemetry: OpenTelemetryConfiguration = .init(),
      instrumentations: Instrumentations = .all,
      openClaw: OpenClawConfiguration = .disabled,
      proxy: ProxyConfiguration? = nil,
      aiAPIHosts: Set<String> = HTTPAIInstrumentation.defaultAIHosts,
      excludedCoreMLModels: Set<String> = [],
      profiling: Profiling = .init()
    ) {
      self.privacy = privacy
      self.openTelemetry = openTelemetry
      self.instrumentations = instrumentations
      self.openClaw = openClaw
      self.proxy = proxy
      self.aiAPIHosts = aiAPIHosts
      self.excludedCoreMLModels = excludedCoreMLModels
      self.profiling = profiling
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

  /// One-line auto-instrumentation setup.
  ///
  /// Configures OpenTelemetry, installs Terra, and enables auto-instrumentation
  /// for CoreML predictions and HTTP AI API calls.
  ///
  /// ```swift
  /// import Terra
  /// try Terra.start()
  /// ```
  ///
  /// After calling `start()`, every CoreML prediction and HTTP request to known
  /// AI API endpoints will automatically produce OpenTelemetry spans with
  /// GenAI semantic convention attributes.
  ///
  /// Foundation Models and MLX wrappers are used independently via their
  /// respective modules (`TerraFoundationModels`, `TerraMLX`).
  public static func start(_ config: AutoInstrumentConfiguration) throws {
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

  @available(*, deprecated, message: "Use Terra.Configuration(preset:) instead.")
  public enum StartProfile: Sendable {
    case quickstart
    case production
    case diagnostics

    public var configuration: AutoInstrumentConfiguration {
      switch self {
      case .quickstart:
        return .init(
          privacy: .init(contentPolicy: .optIn, redaction: .hashHMACSHA256),
          openTelemetry: .init(
            enableTraces: true,
            enableMetrics: true,
            enableLogs: false,
            enableSessions: true,
            metricsExportInterval: 60
          ),
          instrumentations: [.coreML, .httpAIAPIs],
          openClaw: .disabled,
          profiling: .init()
        )

      case .production:
        return .init(
          privacy: .init(contentPolicy: .optIn, redaction: .hashHMACSHA256),
          openTelemetry: .init(
            enableTraces: true,
            enableMetrics: true,
            enableLogs: false,
            persistence: .init(
              storageURL: Terra.defaultPersistenceStorageURL(),
              performancePreset: .default
            )
          ),
          instrumentations: [.coreML, .httpAIAPIs],
          openClaw: .disabled,
          profiling: .init()
        )

      case .diagnostics:
        return .init(
          privacy: .init(contentPolicy: .optIn, redaction: .hashHMACSHA256),
          openTelemetry: .init(
            enableTraces: true,
            enableMetrics: true,
            enableLogs: true,
            enableSignposts: true,
            enableSessions: true,
            otlpTracesEndpoint: URL(string: "http://127.0.0.1:4318/v1/traces")!,
            otlpMetricsEndpoint: URL(string: "http://127.0.0.1:4318/v1/metrics")!,
            otlpLogsEndpoint: URL(string: "http://127.0.0.1:4318/v1/logs")!,
            metricsExportInterval: 15,
            persistence: .init(
              storageURL: Terra.defaultPersistenceStorageURL(),
              performancePreset: .default
            ),
            resourceAttributes: ["terra.profile": .string("diagnostics")]
          ),
          instrumentations: [.coreML, .httpAIAPIs, .openClawDiagnostics],
          openClaw: .init(mode: .diagnosticsOnly),
          profiling: .init(enableMemoryProfiler: true, enableMetalProfiler: true)
        )
      }
    }
  }

  @available(*, deprecated, message: "Mutate Terra.Configuration directly, then call Terra.start(config).")
  public static func start(
    _ preset: StartProfile,
    configure: (inout AutoInstrumentConfiguration) throws -> Void = { _ in }
  ) throws {
    var config = preset.configuration
    try configure(&config)
    try start(config)
  }

  @available(*, deprecated, message: "Use Terra.start(_:configure:) instead.")
  @discardableResult
  public static func bootstrap(
    _ preset: StartProfile = .quickstart,
    configure: (inout AutoInstrumentConfiguration) throws -> Void = { _ in }
  ) throws -> AutoInstrumentConfiguration {
    var config = preset.configuration
    try configure(&config)
    try start(config)
    return config
  }

  @available(*, deprecated, message: "Use Terra.start(_:configure:) instead (unlabeled first parameter).")
  public static func start(
    preset: StartProfile,
    configure: (inout AutoInstrumentConfiguration) throws -> Void = { _ in }
  ) throws {
    try start(preset, configure: configure)
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
}
