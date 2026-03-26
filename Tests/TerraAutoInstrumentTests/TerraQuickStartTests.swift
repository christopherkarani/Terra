import Testing
@testable import Terra
@testable import TerraCore

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

    let preset = Terra.Configuration(preset: .quickstart)
    #expect(preset.privacy == .redacted)

    await Terra.reset()
  }
}
