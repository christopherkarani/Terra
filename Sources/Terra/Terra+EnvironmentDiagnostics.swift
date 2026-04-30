import Foundation

#if canImport(CTerraBridge)
  import CTerraBridge
#endif

#if canImport(CTerraANEBridge)
  import CTerraANEBridge
#endif

extension Terra {
  /// Availability state for a runtime probe checked by `diagnoseEnvironment()`.
  public enum EnvironmentProbeState: String, Sendable, Hashable {
    case available
    case unavailable
    case active
    case inactive
    case unknown
  }

  /// A structured remediation returned by `diagnoseEnvironment()`.
  public struct EnvironmentFix: Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
      self.code = code
      self.message = message
    }
  }

  /// Current Terra tracing provider availability.
  public struct TracingDiagnostics: Sendable {
    public let tracerProvider: EnvironmentProbeState
    public let loggerProvider: EnvironmentProbeState
    public let managedOpenTelemetryProviders: EnvironmentProbeState
    public let lifecycleState: LifecycleState

    public init(
      tracerProvider: EnvironmentProbeState,
      loggerProvider: EnvironmentProbeState,
      managedOpenTelemetryProviders: EnvironmentProbeState,
      lifecycleState: LifecycleState
    ) {
      self.tracerProvider = tracerProvider
      self.loggerProvider = loggerProvider
      self.managedOpenTelemetryProviders = managedOpenTelemetryProviders
      self.lifecycleState = lifecycleState
    }
  }

  /// Native Terra C ABI bridge availability.
  public struct NativeLibraryDiagnostics: Sendable {
    public let moduleName: String
    public let importable: Bool
    public let availability: EnvironmentProbeState
    public let version: String?

    public init(
      moduleName: String,
      importable: Bool,
      availability: EnvironmentProbeState,
      version: String?
    ) {
      self.moduleName = moduleName
      self.importable = importable
      self.availability = availability
      self.version = version
    }
  }

  /// Terra backend routing availability across Swift OpenTelemetry and native bridge paths.
  public struct BackendDiagnostics: Sendable {
    public let swiftOpenTelemetry: EnvironmentProbeState
    public let nativeBridge: EnvironmentProbeState
    public let activeBackend: String

    public init(
      swiftOpenTelemetry: EnvironmentProbeState,
      nativeBridge: EnvironmentProbeState,
      activeBackend: String
    ) {
      self.swiftOpenTelemetry = swiftOpenTelemetry
      self.nativeBridge = nativeBridge
      self.activeBackend = activeBackend
    }
  }

  /// ANE runtime probe state. This reports probe/collection availability without starting collection.
  public struct ANEDiagnostics: Sendable {
    public let probeSource: String
    public let importable: Bool
    public let hardwareAvailability: EnvironmentProbeState
    public let collectionState: EnvironmentProbeState

    public init(
      probeSource: String,
      importable: Bool,
      hardwareAvailability: EnvironmentProbeState,
      collectionState: EnvironmentProbeState
    ) {
      self.probeSource = probeSource
      self.importable = importable
      self.hardwareAvailability = hardwareAvailability
      self.collectionState = collectionState
    }
  }

  /// Platform fields relevant to Terra runtime behavior.
  public struct PlatformDiagnostics: Sendable {
    public let osName: String
    public let osVersion: String
    public let architecture: String
    public let isSimulator: Bool
    public let processName: String

    public init(
      osName: String,
      osVersion: String,
      architecture: String,
      isSimulator: Bool,
      processName: String
    ) {
      self.osName = osName
      self.osVersion = osVersion
      self.architecture = architecture
      self.isSimulator = isSimulator
      self.processName = processName
    }
  }

  /// Toolchain assumptions compiled into this package.
  public struct ToolingDiagnostics: Sendable {
    public let swiftToolsVersion: String
    public let compilerCompatibility: String
    public let packageCompatibility: String

    public init(
      swiftToolsVersion: String,
      compilerCompatibility: String,
      packageCompatibility: String
    ) {
      self.swiftToolsVersion = swiftToolsVersion
      self.compilerCompatibility = compilerCompatibility
      self.packageCompatibility = packageCompatibility
    }
  }

  /// Full runtime diagnostics report for local setup, platform support, native bridge, and ANE probes.
  public struct EnvironmentDiagnosticsReport: Sendable {
    public let tracing: TracingDiagnostics
    public let backend: BackendDiagnostics
    public let nativeLibrary: NativeLibraryDiagnostics
    public let platform: PlatformDiagnostics
    public let tooling: ToolingDiagnostics
    public let ane: ANEDiagnostics
    public let recommendedFixes: [EnvironmentFix]
    public let isReadyForTracing: Bool

    public init(
      tracing: TracingDiagnostics,
      backend: BackendDiagnostics,
      nativeLibrary: NativeLibraryDiagnostics,
      platform: PlatformDiagnostics,
      tooling: ToolingDiagnostics,
      ane: ANEDiagnostics,
      recommendedFixes: [EnvironmentFix],
      isReadyForTracing: Bool
    ) {
      self.tracing = tracing
      self.backend = backend
      self.nativeLibrary = nativeLibrary
      self.platform = platform
      self.tooling = tooling
      self.ane = ane
      self.recommendedFixes = recommendedFixes
      self.isReadyForTracing = isReadyForTracing
    }
  }

  /// Returns structured local runtime diagnostics without starting profilers or exporting telemetry.
  ///
  /// `diagnoseEnvironment()` complements `diagnose()` with lower-level runtime
  /// probes for provider availability, native bridge importability, ANE probe
  /// state, platform fields, and Swift package/tooling assumptions.
  public static func diagnoseEnvironment() -> EnvironmentDiagnosticsReport {
    let tracing = TracingDiagnostics(
      tracerProvider: Runtime.shared.tracerProvider != nil || _hasInstalledOpenTelemetryProviders ? .available : .unavailable,
      loggerProvider: Runtime.shared.loggerProvider != nil || _hasInstalledOpenTelemetryProviders ? .available : .unavailable,
      managedOpenTelemetryProviders: _hasInstalledOpenTelemetryProviders ? .available : .unavailable,
      lifecycleState: Runtime.shared.lifecycleState
    )
    let nativeLibrary = _nativeLibraryDiagnostics()
    let backend = _backendDiagnostics(tracing: tracing, nativeLibrary: nativeLibrary)
    let platform = _platformDiagnostics()
    let tooling = _toolingDiagnostics()
    let ane = _aneDiagnostics()
    let recommendedFixes = _environmentFixes(
      tracing: tracing,
      nativeLibrary: nativeLibrary,
      ane: ane
    )
    let isReadyForTracing = tracing.tracerProvider == .available

    return EnvironmentDiagnosticsReport(
      tracing: tracing,
      backend: backend,
      nativeLibrary: nativeLibrary,
      platform: platform,
      tooling: tooling,
      ane: ane,
      recommendedFixes: recommendedFixes,
      isReadyForTracing: isReadyForTracing
    )
  }

  private static func _nativeLibraryDiagnostics() -> NativeLibraryDiagnostics {
    #if canImport(CTerraBridge)
      let version = terra_get_version()
      return NativeLibraryDiagnostics(
        moduleName: "CTerraBridge",
        importable: true,
        availability: .available,
        version: "\(version.major).\(version.minor).\(version.patch)"
      )
    #else
      return NativeLibraryDiagnostics(
        moduleName: "CTerraBridge",
        importable: false,
        availability: .unavailable,
        version: nil
      )
    #endif
  }

  private static func _backendDiagnostics(
    tracing: TracingDiagnostics,
    nativeLibrary: NativeLibraryDiagnostics
  ) -> BackendDiagnostics {
    let swiftOpenTelemetry = tracing.tracerProvider == .available ? EnvironmentProbeState.available : .unavailable
    let activeBackend: String
    if swiftOpenTelemetry == .available {
      activeBackend = "swift-opentelemetry"
    } else if nativeLibrary.availability == .available {
      activeBackend = "native-bridge-available"
    } else {
      activeBackend = "none"
    }

    return BackendDiagnostics(
      swiftOpenTelemetry: swiftOpenTelemetry,
      nativeBridge: nativeLibrary.availability,
      activeBackend: activeBackend
    )
  }

  private static func _aneDiagnostics() -> ANEDiagnostics {
    #if canImport(CTerraANEBridge)
      return ANEDiagnostics(
        probeSource: "CTerraANEBridge",
        importable: true,
        hardwareAvailability: terra_ane_is_available() ? .available : .unavailable,
        collectionState: terra_ane_is_collecting() ? .active : .inactive
      )
    #else
      return ANEDiagnostics(
        probeSource: "CTerraANEBridge",
        importable: false,
        hardwareAvailability: .unknown,
        collectionState: .unknown
      )
    #endif
  }

  private static func _platformDiagnostics() -> PlatformDiagnostics {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return PlatformDiagnostics(
      osName: _osName(),
      osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
      architecture: _architectureName(),
      isSimulator: _isSimulatorRuntime(),
      processName: ProcessInfo.processInfo.processName
    )
  }

  private static func _toolingDiagnostics() -> ToolingDiagnostics {
    ToolingDiagnostics(
      swiftToolsVersion: "5.9",
      compilerCompatibility: _compilerCompatibility(),
      packageCompatibility: "Compile-friendly for Swift tools version 5.9; diagnostics use additive public API only."
    )
  }

  private static func _environmentFixes(
    tracing: TracingDiagnostics,
    nativeLibrary: NativeLibraryDiagnostics,
    ane: ANEDiagnostics
  ) -> [EnvironmentFix] {
    var fixes: [EnvironmentFix] = []

    if tracing.tracerProvider == .unavailable {
      fixes.append(EnvironmentFix(
        code: "INSTALL_TRACER_PROVIDER",
        message: "Call Terra.quickStart(), Terra.start(...), or install Terra with a tracer provider before expecting spans."
      ))
    }

    if nativeLibrary.availability == .unavailable {
      fixes.append(EnvironmentFix(
        code: "BUILD_NATIVE_LIBRARY",
        message: "Build or include libtera/CTerraBridge when you need the native backend; the Swift OpenTelemetry path can still run without it."
      ))
    }

    if !ane.importable {
      fixes.append(EnvironmentFix(
        code: "IMPORT_ANE_PROFILER",
        message: "Import the ANE profiler target only in builds that explicitly accept private API constraints; diagnostics will not start collection."
      ))
    } else if ane.collectionState == .inactive {
      fixes.append(EnvironmentFix(
        code: "ANE_COLLECTION_INACTIVE",
        message: "ANE probing is available but collection is inactive. Start the ANE profiler only around code paths where private API use is acceptable."
      ))
    }

    return fixes
  }

  private static func _osName() -> String {
    #if os(macOS)
      return "macOS"
    #elseif os(iOS)
      return "iOS"
    #elseif os(tvOS)
      return "tvOS"
    #elseif os(watchOS)
      return "watchOS"
    #elseif os(visionOS)
      return "visionOS"
    #elseif os(Linux)
      return "Linux"
    #else
      return "unknown"
    #endif
  }

  private static func _architectureName() -> String {
    #if arch(arm64)
      return "arm64"
    #elseif arch(x86_64)
      return "x86_64"
    #elseif arch(arm)
      return "arm"
    #elseif arch(i386)
      return "i386"
    #else
      return "unknown"
    #endif
  }

  private static func _isSimulatorRuntime() -> Bool {
    #if targetEnvironment(simulator)
      return true
    #else
      return false
    #endif
  }

  private static func _compilerCompatibility() -> String {
    #if compiler(>=6.0)
      return "Swift 6 or newer"
    #elseif compiler(>=5.10)
      return "Swift 5.10"
    #elseif compiler(>=5.9)
      return "Swift 5.9"
    #else
      return "Older than Swift 5.9"
    #endif
  }
}
