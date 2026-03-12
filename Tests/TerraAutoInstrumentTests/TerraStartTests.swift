import Foundation
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

  // MARK: - Terra.start() Smoke Tests

  @Test("Terra.start() with no features does not crash")
  func terraStartWithNoFeaturesDoesNotCrash() async throws {
    Terra.resetOpenTelemetryForTesting()
    await Terra.reset()
    defer { Terra.resetOpenTelemetryForTesting() }

    var config = Terra.Configuration(preset: .quickstart)
    config.features = []
    try await Terra.start(config)
    await Terra.reset()
  }

  @Test("Terra.start() throws already_started when called twice with different config")
  func terraStartThrowsAlreadyStartedOnSecondCall() async throws {
    Terra.resetOpenTelemetryForTesting()
    await Terra.reset()
    defer { Terra.resetOpenTelemetryForTesting() }

    var config1 = Terra.Configuration(preset: .quickstart)
    config1.features = []
    try await Terra.start(config1)

    var config2 = config1
    config2.destination = .endpoint(URL(string: "http://other-collector:4318")!)
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

    var config = Terra.Configuration(preset: .quickstart)
    config.features = []

    try await Terra.start(config)
    try await Terra.start(config)
    await Terra.reset()
  }
}
