import Testing
@testable import Terra
@testable import TerraCore

@Test("Configuration has sensible defaults")
func configurationDefaults() {
  let config = Terra.Configuration()
  #expect(config.privacy == .redacted)
  #expect(config.serviceName == nil)
  #expect(config.samplingRatio == nil)
  #expect(config.metricsInterval == 60)
  #expect(config.enableSignposts == true)
  #expect(config.enableSessions == true)
}

@Test("Configuration default profiling has both profilers disabled")
func configurationDefaultProfilingDisabled() {
  let config = Terra.Configuration()
  #expect(config.profiling.enableMemoryProfiler == false)
  #expect(config.profiling.enableMetalProfiler == false)
}

@Test("Configuration default openClaw mode is disabled")
func configurationDefaultOpenClawDisabled() {
  let config = Terra.Configuration()
  #expect(config.openClaw.mode == .disabled)
}

@Test("Configuration default excludedCoreMLModels is empty")
func configurationDefaultExcludedCoreMLModelsEmpty() {
  let config = Terra.Configuration()
  #expect(config.excludedCoreMLModels.isEmpty)
}

@Test("Configuration default enableLogs is false")
func configurationDefaultEnableLogsFalse() {
  let config = Terra.Configuration()
  #expect(config.enableLogs == false)
}

@Test("Preset.quickstart creates correct configuration")
func quickstartPreset() {
  let config = Terra.Configuration(preset: .quickstart)
  #expect(config.privacy == .redacted)
  #expect(config.persistence == nil)
}

@Test("Preset.production enables persistence")
func productionPreset() {
  let config = Terra.Configuration(preset: .production)
  #expect(config.persistence != nil)
}

@Test("Preset.diagnostics enables diagnostics instrumentation")
func diagnosticsPreset() {
  let config = Terra.Configuration(preset: .diagnostics)
  #expect(config.persistence != nil)
  #expect(config.instrumentations.contains(.openClawDiagnostics))
  #expect(config.resourceAttributes["terra.profile"] == "diagnostics")
}

@Test("Diagnostics preset enables both profilers")
func diagnosticsPresetEnablesProfilers() {
  let config = Terra.Configuration(preset: .diagnostics)
  #expect(config.profiling.enableMemoryProfiler == true)
  #expect(config.profiling.enableMetalProfiler == true)
}

@Test("Diagnostics preset sets openClaw mode to diagnosticsOnly")
func diagnosticsPresetSetsOpenClawDiagnostics() {
  let config = Terra.Configuration(preset: .diagnostics)
  #expect(config.openClaw.mode == .diagnosticsOnly)
}

@Test("Diagnostics preset sets enableLogs to true")
func diagnosticsPresetEnablesLogs() {
  let config = Terra.Configuration(preset: .diagnostics)
  #expect(config.enableLogs == true)
}

@Test("Quickstart preset keeps profilers disabled")
func quickstartPresetKeepsProfilersDisabled() {
  let config = Terra.Configuration(preset: .quickstart)
  #expect(config.profiling.enableMemoryProfiler == false)
  #expect(config.profiling.enableMetalProfiler == false)
}

@Test("Quickstart preset keeps openClaw disabled")
func quickstartPresetKeepsOpenClawDisabled() {
  let config = Terra.Configuration(preset: .quickstart)
  #expect(config.openClaw.mode == .disabled)
}

@Test("Production preset keeps profilers disabled")
func productionPresetKeepsProfilersDisabled() {
  let config = Terra.Configuration(preset: .production)
  #expect(config.profiling.enableMemoryProfiler == false)
  #expect(config.profiling.enableMetalProfiler == false)
}

@Test("Production preset keeps openClaw disabled")
func productionPresetKeepsOpenClawDisabled() {
  let config = Terra.Configuration(preset: .production)
  #expect(config.openClaw.mode == .disabled)
}

// MARK: - Conversion Tests

@Test("Custom profiling value survives start configuration conversion")
func profilingSurvivesConversion() {
  var config = Terra.Configuration()
  config.profiling = .init(enableMemoryProfiler: true, enableMetalProfiler: true)
  let resolved = config.asAutoInstrumentConfiguration()
  #expect(resolved.profiling.enableMemoryProfiler == true)
  #expect(resolved.profiling.enableMetalProfiler == true)
}

@Test("Custom openClaw value survives start configuration conversion")
func openClawSurvivesConversion() {
  var config = Terra.Configuration()
  config.openClaw = .init(mode: .diagnosticsOnly)
  let resolved = config.asAutoInstrumentConfiguration()
  #expect(resolved.openClaw.mode == .diagnosticsOnly)
}

@Test("Custom excludedCoreMLModels survives start configuration conversion")
func excludedCoreMLModelsSurvivesConversion() {
  var config = Terra.Configuration()
  config.excludedCoreMLModels = ["MyModel", "OtherModel"]
  let resolved = config.asAutoInstrumentConfiguration()
  #expect(resolved.excludedCoreMLModels == ["MyModel", "OtherModel"])
}

@Test("enableLogs = true maps to OpenTelemetry enableLogs = true")
func enableLogsMapsCorrectly() {
  var config = Terra.Configuration()
  config.enableLogs = true
  let resolved = config.asAutoInstrumentConfiguration()
  #expect(resolved.openTelemetry.enableLogs == true)
}

@Test("enableLogs = false maps to OpenTelemetry enableLogs = false")
func enableLogsFalseMapsCorrectly() {
  let config = Terra.Configuration()
  let resolved = config.asAutoInstrumentConfiguration()
  #expect(resolved.openTelemetry.enableLogs == false)
}

@Suite("Configuration canonical start", .serialized)
final class ConfigurationCanonicalStartTests {
  init() {
    Terra.lockTestingIsolation()
    Terra.resetOpenTelemetryForTesting()
  }

  deinit {
    Terra.resetOpenTelemetryForTesting()
    Terra.unlockTestingIsolation()
  }

  @Test("start with Configuration delegates correctly")
  func startWithConfiguration() async throws {
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
}
