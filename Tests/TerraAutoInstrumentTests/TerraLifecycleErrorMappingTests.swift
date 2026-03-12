import Foundation
import Testing
@testable import Terra
@testable import TerraCore

@Suite("Terra lifecycle error mapping", .serialized)
final class TerraLifecycleErrorMappingTests {
  init() {
    Terra.lockTestingIsolation()
    Terra.resetOpenTelemetryForTesting()
  }

  deinit {
    Terra.resetOpenTelemetryForTesting()
    Terra.unlockTestingIsolation()
  }

  @Test("invalid endpoint maps to invalid_endpoint")
  func invalidEndpointMapsToTerraError() async {
    Terra.resetOpenTelemetryForTesting()
    await Terra.reset()

    var config = makeConfig()
    config.destination = .endpoint(URL(string: "ftp://127.0.0.1:4318")!)

    do {
      try await Terra.start(config)
      #expect(Bool(false), "Expected Terra.start to throw invalid_endpoint.")
    } catch let error as Terra.TerraError {
      #expect(error.code == .invalid_endpoint)
    } catch {
      #expect(Bool(false), "Unexpected error type: \(error)")
    }
  }

  @Test("persistence storage setup failures map to persistence_setup_failed")
  func persistenceSetupFailureMapsToTerraError() async throws {
    Terra.resetOpenTelemetryForTesting()
    await Terra.reset()

    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("terra-persistence-file-\(UUID().uuidString)")
    try Data("not-a-directory".utf8).write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    var config = makeConfig()
    config.persistence = .balanced(fileURL)

    do {
      try await Terra.start(config)
      #expect(Bool(false), "Expected Terra.start to throw persistence_setup_failed.")
    } catch let error as Terra.TerraError {
      #expect(error.code == .persistence_setup_failed)
    } catch {
      #expect(Bool(false), "Unexpected error type: \(error)")
    }
  }

  @Test("starting with different config while running maps to already_started")
  func alreadyStartedMapsToTerraError() async throws {
    Terra.resetOpenTelemetryForTesting()
    await Terra.reset()

    var config = makeConfig()
    config.destination = .endpoint(URL(string: "http://collector-a:4318")!)
    try await Terra.start(config)

    var different = config
    different.destination = .endpoint(URL(string: "http://collector-b:4318")!)

    do {
      try await Terra.start(different)
      #expect(Bool(false), "Expected Terra.start to throw already_started.")
    } catch let error as Terra.TerraError {
      #expect(error.code == .already_started)
    } catch {
      #expect(Bool(false), "Unexpected error type: \(error)")
    }
  }

  @Test("reconfigure while stopped maps to invalid_lifecycle_state")
  func invalidStateTransitionMapsToTerraError() async {
    Terra.resetOpenTelemetryForTesting()
    await Terra.reset()

    do {
      try await Terra.reconfigure(makeConfig())
      #expect(Bool(false), "Expected Terra.reconfigure to throw invalid_lifecycle_state when stopped.")
    } catch let error as Terra.TerraError {
      #expect(error.code == .invalid_lifecycle_state)
    } catch {
      #expect(Bool(false), "Unexpected error type: \(error)")
    }
  }
}

private func makeConfig() -> Terra.Configuration {
  var config = Terra.Configuration(preset: .quickstart)
  config.features = []
  return config
}
