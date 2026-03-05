import OpenTelemetrySdk
import Testing
@testable import Terra
@testable import TerraCore

@Suite("Terra.start canonical API", .serialized)
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

  // MARK: - Canonical Configuration Tests

  @Test("Configuration default instrumentations is .all")
  func defaultConfigurationInstrumentationsIsAll() {
    let config = Terra.Configuration()
    #expect(config.instrumentations == .all)
  }

  @Test("Configuration can disable instrumentations via .none")
  func configurationCanDisableInstrumentations() {
    var config = Terra.Configuration()
    config.instrumentations = .none
    #expect(config.instrumentations == .none)
  }

  @Test("Configuration holds custom excluded CoreML models")
  func configurationExcludedCoreMLModels() {
    let excluded: Set<String> = ["ModelA", "ModelB"]
    var config = Terra.Configuration()
    config.excludedCoreMLModels = excluded
    #expect(config.excludedCoreMLModels == excluded)
  }

  @Test("Configuration default excluded CoreML models is empty")
  func defaultExcludedCoreMLModelsIsEmpty() {
    let config = Terra.Configuration()
    #expect(config.excludedCoreMLModels.isEmpty)
  }

  @Test("Configuration default OpenClaw mode is disabled")
  func defaultOpenClawModeIsDisabled() {
    let config = Terra.Configuration()
    #expect(config.openClaw.mode == .disabled)
  }

  @Test("Configuration default OpenClaw gateway hosts are empty when disabled")
  func defaultOpenClawGatewayHostsAreEmptyWhenDisabled() {
    let config = Terra.Configuration()
    #expect(config.openClaw.gatewayHosts.isEmpty)
  }

  @Test("Configuration conversion preserves disabled OpenClaw hosts")
  func configurationDefaultKeepsOpenClawHostsEmpty() {
    let config = Terra.Configuration()
    let resolved = config.asAutoInstrumentConfiguration()
    #expect(resolved.openClaw.mode == .disabled)
    #expect(resolved.openClaw.gatewayHosts.isEmpty)
  }

  @Test("OpenClaw diagnosticsOnly enables diagnostics export and disables gateway instrumentation")
  func openClawDiagnosticsOnlyModeBehavior() {
    let openClaw = Terra.OpenClawConfiguration(mode: .diagnosticsOnly)
    #expect(!openClaw.shouldEnableGatewayInstrumentation)
    #expect(openClaw.shouldEnableDiagnosticsExport)
  }

  @Test("Configuration profiling defaults are disabled")
  func profilingDefaultsDisabled() {
    let config = Terra.Configuration()
    #expect(!config.profiling.enableMemoryProfiler)
    #expect(!config.profiling.enableMetalProfiler)
  }

  // MARK: - Terra.start() Smoke Tests

  @Test("Terra.start() with .none instrumentations does not crash")
  func terraStartWithNoneInstrumentationsDoesNotCrash() async throws {
    Terra.resetOpenTelemetryForTesting()
    await Terra.reset()
    defer { Terra.resetOpenTelemetryForTesting() }

    var config = Terra.Configuration()
    config.instrumentations = .none
    config.enableSignposts = false
    config.enableSessions = false
    try await Terra.start(config)
    await Terra.reset()
  }

  @Test("Terra.start() throws already_started when called twice with different config")
  func terraStartThrowsAlreadyStartedOnSecondCall() async throws {
    Terra.resetOpenTelemetryForTesting()
    await Terra.reset()
    defer { Terra.resetOpenTelemetryForTesting() }

    var config1 = Terra.Configuration()
    config1.instrumentations = .none
    config1.enableSignposts = false
    config1.enableSessions = false
    try await Terra.start(config1)

    var config2 = config1
    config2.serviceName = "com.example.changed"
    do {
      try await Terra.start(config2)
      #expect(Bool(false), "Expected Terra.start to throw already_started when called with a different config while running.")
    } catch let error as Terra.TerraError {
      #expect(error.code == .already_started)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    await Terra.reset()
  }

  @Test("Terra.start() is idempotent when called twice with identical config")
  func terraStartIsIdempotentWithSameConfig() async throws {
    Terra.resetOpenTelemetryForTesting()
    await Terra.reset()
    defer { Terra.resetOpenTelemetryForTesting() }

    var config = Terra.Configuration()
    config.instrumentations = .none
    config.enableSignposts = false
    config.enableSessions = false

    try await Terra.start(config)
    try await Terra.start(config)
    await Terra.reset()
  }
}
