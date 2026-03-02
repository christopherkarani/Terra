import Testing
import Terra
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

// MARK: - Preset Parity Tests

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

@Test("V3Configuration typealias resolves to Configuration")
func v3TypealiasWorks() {
  let _: Terra.V3Configuration = Terra.Configuration()
}

// MARK: - Conversion Round-Trip Tests

@Test("Custom profiling value survives asAutoInstrumentConfiguration conversion")
func profilingSurvivesConversion() {
  var config = Terra.Configuration()
  config.profiling = .init(enableMemoryProfiler: true, enableMetalProfiler: true)
  let auto = config.asAutoInstrumentConfiguration()
  #expect(auto.profiling.enableMemoryProfiler == true)
  #expect(auto.profiling.enableMetalProfiler == true)
}

@Test("Custom openClaw value survives asAutoInstrumentConfiguration conversion")
func openClawSurvivesConversion() {
  var config = Terra.Configuration()
  config.openClaw = .init(mode: .diagnosticsOnly)
  let auto = config.asAutoInstrumentConfiguration()
  #expect(auto.openClaw.mode == .diagnosticsOnly)
}

@Test("Custom excludedCoreMLModels survives asAutoInstrumentConfiguration conversion")
func excludedCoreMLModelsSurvivesConversion() {
  var config = Terra.Configuration()
  config.excludedCoreMLModels = ["MyModel", "OtherModel"]
  let auto = config.asAutoInstrumentConfiguration()
  #expect(auto.excludedCoreMLModels == ["MyModel", "OtherModel"])
}

@Test("enableLogs = true maps to openTelemetry.enableLogs = true in conversion")
func enableLogsMapsCorrectly() {
  var config = Terra.Configuration()
  config.enableLogs = true
  let auto = config.asAutoInstrumentConfiguration()
  #expect(auto.openTelemetry.enableLogs == true)
}

@Test("enableLogs = false maps to openTelemetry.enableLogs = false in conversion")
func enableLogsFalseMapsCorrectly() {
  let config = Terra.Configuration()
  let auto = config.asAutoInstrumentConfiguration()
  #expect(auto.openTelemetry.enableLogs == false)
}

// MARK: - Preset Equivalence Tests

@Suite("Preset equivalence: Configuration(preset:) vs StartProfile")
struct PresetEquivalenceTests {
  @Test("Quickstart preset equivalence",
        arguments: [("quickstart", Terra.Configuration.Preset.quickstart, Terra.StartProfile.quickstart)])
  func quickstartEquivalence(label: String, preset: Terra.Configuration.Preset, profile: Terra.StartProfile) {
    let fromConfig = Terra.Configuration(preset: preset).asAutoInstrumentConfiguration()
    let fromProfile = profile.configuration

    // Privacy
    #expect(fromConfig.privacy.contentPolicy == fromProfile.privacy.contentPolicy)
    #expect(fromConfig.privacy.redaction == fromProfile.privacy.redaction)
    #expect(fromConfig.privacy.anonymizationKey == fromProfile.privacy.anonymizationKey)

    // OpenTelemetry
    #expect(fromConfig.openTelemetry.enableTraces == fromProfile.openTelemetry.enableTraces)
    #expect(fromConfig.openTelemetry.enableMetrics == fromProfile.openTelemetry.enableMetrics)
    #expect(fromConfig.openTelemetry.enableLogs == fromProfile.openTelemetry.enableLogs)
    #expect(fromConfig.openTelemetry.enableSignposts == fromProfile.openTelemetry.enableSignposts)
    #expect(fromConfig.openTelemetry.enableSessions == fromProfile.openTelemetry.enableSessions)
    #expect(fromConfig.openTelemetry.metricsExportInterval == fromProfile.openTelemetry.metricsExportInterval)
    #expect(fromConfig.openTelemetry.persistence == fromProfile.openTelemetry.persistence)

    // Instrumentations
    #expect(fromConfig.instrumentations == fromProfile.instrumentations)

    // OpenClaw
    #expect(fromConfig.openClaw.mode == fromProfile.openClaw.mode)

    // Profiling
    #expect(fromConfig.profiling.enableMemoryProfiler == fromProfile.profiling.enableMemoryProfiler)
    #expect(fromConfig.profiling.enableMetalProfiler == fromProfile.profiling.enableMetalProfiler)

    // Excluded models
    #expect(fromConfig.excludedCoreMLModels == fromProfile.excludedCoreMLModels)
  }

  @Test("Production preset equivalence")
  func productionEquivalence() {
    let fromConfig = Terra.Configuration(preset: .production).asAutoInstrumentConfiguration()
    let fromProfile = Terra.StartProfile.production.configuration

    #expect(fromConfig.privacy.contentPolicy == fromProfile.privacy.contentPolicy)
    #expect(fromConfig.privacy.redaction == fromProfile.privacy.redaction)
    #expect(fromConfig.openTelemetry.enableTraces == fromProfile.openTelemetry.enableTraces)
    #expect(fromConfig.openTelemetry.enableMetrics == fromProfile.openTelemetry.enableMetrics)
    #expect(fromConfig.openTelemetry.enableLogs == fromProfile.openTelemetry.enableLogs)
    #expect(fromConfig.openTelemetry.enableSignposts == fromProfile.openTelemetry.enableSignposts)
    #expect(fromConfig.openTelemetry.enableSessions == fromProfile.openTelemetry.enableSessions)
    #expect(fromConfig.openTelemetry.metricsExportInterval == fromProfile.openTelemetry.metricsExportInterval)
    #expect(fromConfig.openTelemetry.persistence == fromProfile.openTelemetry.persistence)
    #expect(fromConfig.instrumentations == fromProfile.instrumentations)
    #expect(fromConfig.openClaw.mode == fromProfile.openClaw.mode)
    #expect(fromConfig.profiling.enableMemoryProfiler == fromProfile.profiling.enableMemoryProfiler)
    #expect(fromConfig.profiling.enableMetalProfiler == fromProfile.profiling.enableMetalProfiler)
    #expect(fromConfig.excludedCoreMLModels == fromProfile.excludedCoreMLModels)
  }

  @Test("Diagnostics preset equivalence")
  func diagnosticsEquivalence() {
    let fromConfig = Terra.Configuration(preset: .diagnostics).asAutoInstrumentConfiguration()
    let fromProfile = Terra.StartProfile.diagnostics.configuration

    #expect(fromConfig.privacy.contentPolicy == fromProfile.privacy.contentPolicy)
    #expect(fromConfig.privacy.redaction == fromProfile.privacy.redaction)
    #expect(fromConfig.openTelemetry.enableTraces == fromProfile.openTelemetry.enableTraces)
    #expect(fromConfig.openTelemetry.enableMetrics == fromProfile.openTelemetry.enableMetrics)
    #expect(fromConfig.openTelemetry.enableLogs == fromProfile.openTelemetry.enableLogs)
    #expect(fromConfig.openTelemetry.enableSignposts == fromProfile.openTelemetry.enableSignposts)
    #expect(fromConfig.openTelemetry.enableSessions == fromProfile.openTelemetry.enableSessions)
    #expect(fromConfig.openTelemetry.metricsExportInterval == fromProfile.openTelemetry.metricsExportInterval)
    #expect(fromConfig.openTelemetry.persistence == fromProfile.openTelemetry.persistence)
    #expect(fromConfig.openTelemetry.resourceAttributes == fromProfile.openTelemetry.resourceAttributes)
    #expect(fromConfig.instrumentations == fromProfile.instrumentations)
    #expect(fromConfig.openClaw.mode == fromProfile.openClaw.mode)
    #expect(fromConfig.profiling.enableMemoryProfiler == fromProfile.profiling.enableMemoryProfiler)
    #expect(fromConfig.profiling.enableMetalProfiler == fromProfile.profiling.enableMetalProfiler)
    #expect(fromConfig.excludedCoreMLModels == fromProfile.excludedCoreMLModels)
  }
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
  func startWithConfiguration() throws {
    Terra.resetOpenTelemetryForTesting()
    defer { Terra.resetOpenTelemetryForTesting() }
    var config = Terra.Configuration()
    config.instrumentations = .none
    config.enableSignposts = false
    config.enableSessions = false
    try Terra.start(config)
  }
}
