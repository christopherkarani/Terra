import Testing
@testable import Terra
@testable import TerraCore
import TerraMetalProfiler
import TerraSystemProfiler

@Suite("Terra.quickStart", .serialized)
final class TerraQuickStartTests {
  init() {
    Terra.lockTestingIsolation()
    Terra.resetOpenTelemetryForTesting()
  }

  deinit {
    Terra.resetOpenTelemetryForTesting()
    Terra.unlockTestingIsolation()
  }

  @Test("quickStart uses localhost and capturing privacy without changing quickstart preset")
  func quickStartUsesExplicitLocalDefaults() async throws {
    await Terra.reset()

    try await Terra.quickStart()
    let report = Terra.diagnose()

    #expect(report.isHealthy)

    let config = try #require(Terra._installedOpenTelemetryConfiguration)
    #expect(config.otlpTracesEndpoint.absoluteString == "http://localhost:4318/v1/traces")
    #expect(TerraSystemProfiler.isInstalled == true)
    #expect(ThermalMonitor.isInstalled == true)
    #expect(TerraMetalProfiler.isInstalled == true)

    let preset = Terra.Configuration(preset: .quickstart)
    #expect(preset.privacy == .redacted)
    #expect(preset.profiling.isEmpty)

    await Terra.reset()
  }
}
