import Testing
import Terra
@testable import TerraCore
import OpenTelemetrySdk

@Suite("Terra.start / AutoInstrument Tests", .serialized)
final class TerraStartTests {
  init() {
    Terra.lockTestingIsolation()
    Terra.resetOpenTelemetryForTesting()
  }

  deinit {
    Terra.resetOpenTelemetryForTesting()
    Terra.unlockTestingIsolation()
  }

  // MARK: - Terra.Instrumentations OptionSet Tests

  @Test("Instrumentations.none has rawValue 0")
  func instrumentationsNoneIsEmpty() {
    let none = Terra.Instrumentations.none
    #expect(none.rawValue == 0)
    #expect(!none.contains(.coreML))
    #expect(!none.contains(.httpAIAPIs))
    #expect(!none.contains(.proxy))
    #expect(!none.contains(.openClawGateway))
    #expect(!none.contains(.openClawDiagnostics))
  }

  @Test("Instrumentations.all contains core and HTTP defaults")
  func instrumentationsAllContainsBoth() {
    let all = Terra.Instrumentations.all
    #expect(all.contains(.coreML))
    #expect(all.contains(.httpAIAPIs))
    #expect(!all.contains(.openClawGateway))
    #expect(!all.contains(.openClawDiagnostics))
  }

  @Test("Instrumentations can be combined with union")
  func instrumentationsUnion() {
    let combined: Terra.Instrumentations = [.coreML]
    #expect(combined.contains(.coreML))
    #expect(!combined.contains(.httpAIAPIs))
  }

  @Test("Instrumentations rawValues are distinct powers of two")
  func instrumentationsRawValuesAreDistinct() {
    let flags: [Terra.Instrumentations] = [
      .coreML,
      .httpAIAPIs,
      .proxy,
      .openClawGateway,
      .openClawDiagnostics,
    ]
    let values = flags.map(\.rawValue)
    #expect(Set(values).count == values.count)
    #expect(values.allSatisfy { $0 != 0 })
  }

  // MARK: - Terra.AutoInstrumentConfiguration Tests

  @Test("AutoInstrumentConfiguration default instrumentations is .all")
  func defaultConfigurationInstrumentationsIsAll() {
    let config = Terra.AutoInstrumentConfiguration()
    #expect(config.instrumentations == .all)
  }

  @Test("AutoInstrumentConfiguration can be customized with .none")
  func configurationCanBeNone() {
    let config = Terra.AutoInstrumentConfiguration(instrumentations: .none)
    #expect(config.instrumentations == .none)
  }

  @Test("AutoInstrumentConfiguration holds custom excluded CoreML models")
  func configurationExcludedCoreMLModels() {
    let excluded: Set<String> = ["ModelA", "ModelB"]
    let config = Terra.AutoInstrumentConfiguration(excludedCoreMLModels: excluded)
    #expect(config.excludedCoreMLModels == excluded)
  }

  @Test("AutoInstrumentConfiguration default excluded CoreML models is empty")
  func defaultExcludedCoreMLModelsIsEmpty() {
    let config = Terra.AutoInstrumentConfiguration()
    #expect(config.excludedCoreMLModels.isEmpty)
  }

  @Test("AutoInstrumentConfiguration default OpenClaw mode is disabled")
  func defaultOpenClawModeIsDisabled() {
    let config = Terra.AutoInstrumentConfiguration()
    #expect(config.openClaw.mode == .disabled)
  }

  @Test("OpenClaw disabled mode defaults to no gateway hosts")
  func defaultOpenClawGatewayHostsAreEmptyWhenDisabled() {
    let config = Terra.AutoInstrumentConfiguration()
    #expect(config.openClaw.gatewayHosts.isEmpty)
  }

  @Test("OpenClaw diagnosticsOnly enables diagnostics export and disables gateway instrumentation")
  func openClawDiagnosticsOnlyModeBehavior() {
    let openClaw = Terra.OpenClawConfiguration(mode: .diagnosticsOnly)
    #expect(!openClaw.shouldEnableGatewayInstrumentation)
    #expect(openClaw.shouldEnableDiagnosticsExport)
  }

  @Test("AutoInstrumentConfiguration profiling defaults are disabled")
  func profilingDefaultsDisabled() {
    let config = Terra.AutoInstrumentConfiguration()
    #expect(!config.profiling.enableMemoryProfiler)
    #expect(!config.profiling.enableMetalProfiler)
  }

  // MARK: - New Front-Facing API Ergonomics Tests

  @Test("Terra.bootstrap applies configuration overrides and returns effective config")
  func terraBootstrapAppliesOverridesAndReturnsConfig() throws {
    Terra.resetOpenTelemetryForTesting()
    defer { Terra.resetOpenTelemetryForTesting() }

    let config = try Terra.bootstrap(.quickstart) { config in
      config.openTelemetry = .init(
        enableTraces: false,
        enableMetrics: false,
        enableLogs: false,
        enableSignposts: false,
        enableSessions: false
      )
      config.instrumentations = .none
      config.privacy.contentPolicy = .optIn
    }

    #expect(config.instrumentations == .none)
    #expect(config.privacy.contentPolicy == .optIn)
    #expect(!config.openTelemetry.enableTraces)
    #expect(!config.openTelemetry.enableMetrics)
  }

  @Test("Terra.start preset overload is idempotent with identical effective config")
  func terraStartPresetOverloadIsIdempotent() throws {
    Terra.resetOpenTelemetryForTesting()
    defer { Terra.resetOpenTelemetryForTesting() }

    let configure: (inout Terra.AutoInstrumentConfiguration) -> Void = { config in
      config.openTelemetry = .init(
        enableTraces: false,
        enableMetrics: false,
        enableLogs: false,
        enableSignposts: false,
        enableSessions: false
      )
      config.instrumentations = .none
    }

    try Terra.start(.quickstart, configure: configure)
    try Terra.start(.quickstart, configure: configure)
  }

  // MARK: - Terra.start() Smoke Tests
  //
  // Terra.start() calls installOpenTelemetry which throws .alreadyInstalled if called
  // a second time with a different configuration. We test only the .none instrumentations
  // path in isolation via the public API. Each test avoids double-installing by using
  // the DEBUG reset hook.

  @Test("Terra.start() with .none instrumentations does not crash")
  func terraStartWithNoneInstrumentationsDoesNotCrash() throws {
    // Reset any prior install state from other tests or runs
    Terra.resetOpenTelemetryForTesting()
    defer { Terra.resetOpenTelemetryForTesting() }

    let config = Terra.AutoInstrumentConfiguration(
      openTelemetry: .init(
        enableTraces: false,
        enableMetrics: false,
        enableLogs: false,
        enableSignposts: false,
        enableSessions: false
      ),
      instrumentations: .none
    )

    // Should not throw
    try Terra.start(config)
  }

  @Test("Terra.start() throws alreadyInstalled when called twice with different config")
  func terraStartThrowsAlreadyInstalledOnSecondCall() throws {
    Terra.resetOpenTelemetryForTesting()
    defer { Terra.resetOpenTelemetryForTesting() }

    let config1 = Terra.AutoInstrumentConfiguration(
      openTelemetry: .init(
        enableTraces: false,
        enableMetrics: false,
        enableLogs: false,
        enableSignposts: false,
        enableSessions: false
      ),
      instrumentations: .none
    )
    try Terra.start(config1)

    // Second call with a different config should throw
    var config2 = config1
    config2.openTelemetry.enableTraces = true
    #expect(throws: Terra.InstallOpenTelemetryError.alreadyInstalled) {
      try Terra.start(config2)
    }
  }

  @Test("Terra.start() is idempotent when called twice with identical config")
  func terraStartIsIdempotentWithSameConfig() throws {
    Terra.resetOpenTelemetryForTesting()
    defer { Terra.resetOpenTelemetryForTesting() }

    let config = Terra.AutoInstrumentConfiguration(
      openTelemetry: .init(
        enableTraces: false,
        enableMetrics: false,
        enableLogs: false,
        enableSignposts: false,
        enableSessions: false
      ),
      instrumentations: .none
    )

    // Two calls with the same config should not throw
    try Terra.start(config)
    try Terra.start(config)
  }
}
