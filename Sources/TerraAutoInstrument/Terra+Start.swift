import Foundation
@_exported import TerraCore
import TerraCoreML
import TerraHTTPInstrument
import TerraMetalProfiler
import TerraSystemProfiler
import OpenTelemetrySdk

extension Terra {
  public enum StartError: Error, Equatable {
    case proxyConfigurationRequired
  }

  /// Configuration for `Terra.start()` auto-instrumentation.
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
  public static func start(_ config: AutoInstrumentConfiguration = .init()) throws {
    // Fail fast on invalid proxy config before mutating global OpenTelemetry/Terra runtime state.
    if config.instrumentations.contains(.proxy), config.proxy == nil {
      throw StartError.proxyConfigurationRequired
    }

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
      let excludedEndpoints: Set<URL> = [
        openTelemetryConfig.otlpTracesEndpoint,
        openTelemetryConfig.otlpMetricsEndpoint,
        openTelemetryConfig.otlpLogsEndpoint,
      ]
      HTTPAIInstrumentation.install(
        hosts: monitoredHosts,
        openClawGatewayHosts: openClawGatewayHosts,
        openClawMode: config.openClaw.modeString,
        excludedEndpoints: excludedEndpoints
      )
    }

    // 5. Optional OpenClaw diagnostics export mode.
    let shouldEnableDiagnostics =
      config.instrumentations.contains(.openClawDiagnostics)
      || config.openClaw.shouldEnableDiagnosticsExport
    if shouldEnableDiagnostics {
      OpenClawDiagnosticsExporter.installIfNeeded(configuration: config.openClaw)
    }
  }
}
