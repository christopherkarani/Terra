import XCTest
@testable import TerraCore

final class TerraLifecycleTests: XCTestCase {

  override func setUp() async throws {
    // Reset both the OTel install state and the Runtime lifecycle state before each test.
    Terra.resetOpenTelemetryForTesting()
  }

  override func tearDown() async throws {
    // Shut down if anything was installed during the test.
    await Terra.shutdown()
  }

  // MARK: - State Query Tests

  func testInitialState_isUninitialized() {
    XCTAssertEqual(Terra.lifecycleState, .uninitialized)
    XCTAssertFalse(Terra.isRunning)
  }

  func testAfterInstall_isRunning() throws {
    let config = minimalConfig()
    try Terra.installOpenTelemetry(config)
    XCTAssertEqual(Terra.lifecycleState, .running)
    XCTAssertTrue(Terra.isRunning)
  }

  func testAfterShutdown_isUninitialized() async throws {
    try Terra.installOpenTelemetry(minimalConfig())
    XCTAssertTrue(Terra.isRunning)

    await Terra.shutdown()

    XCTAssertEqual(Terra.lifecycleState, .uninitialized)
    XCTAssertFalse(Terra.isRunning)
  }

  func testShutdown_whenNotRunning_isIdempotent() async {
    XCTAssertFalse(Terra.isRunning)
    await Terra.shutdown()  // no-op: must not crash
    await Terra.shutdown()  // second call: must not crash
    XCTAssertFalse(Terra.isRunning)
  }

  func testShutdown_isIdempotent_afterInstall() async throws {
    try Terra.installOpenTelemetry(minimalConfig())
    await Terra.shutdown()
    await Terra.shutdown()  // second call: must not crash
    XCTAssertFalse(Terra.isRunning)
  }

  func testStartAfterShutdown_succeeds() async throws {
    let config1 = minimalConfig(port: 14001)
    let config2 = minimalConfig(port: 14002)

    try Terra.installOpenTelemetry(config1)
    XCTAssertTrue(Terra.isRunning)

    await Terra.shutdown()
    XCTAssertFalse(Terra.isRunning)

    // Must succeed — state is uninitialized after shutdown
    XCTAssertNoThrow(try Terra.installOpenTelemetry(config2))
    XCTAssertTrue(Terra.isRunning)
  }

  func testStartSameConfig_isIdempotent() throws {
    let config = minimalConfig()
    try Terra.installOpenTelemetry(config)
    // Second call with identical config: no throw, stays running
    XCTAssertNoThrow(try Terra.installOpenTelemetry(config))
    XCTAssertTrue(Terra.isRunning)
  }

  func testStartDifferentConfig_throwsAlreadyInstalled() throws {
    let config1 = minimalConfig(port: 14001)
    let config2 = minimalConfig(port: 14002)
    try Terra.installOpenTelemetry(config1)
    XCTAssertThrowsError(try Terra.installOpenTelemetry(config2)) { error in
      XCTAssertEqual(error as? Terra.InstallOpenTelemetryError, .alreadyInstalled)
    }
  }
}

// MARK: - Helpers

private func minimalConfig(port: Int = 14099) -> Terra.OpenTelemetryConfiguration {
  Terra.OpenTelemetryConfiguration(
    enableTraces: false,
    enableMetrics: false,
    enableLogs: false,
    enableSignposts: false,
    enableSessions: false,
    otlpTracesEndpoint: URL(string: "http://127.0.0.1:\(port)/v1/traces")!,
    otlpMetricsEndpoint: URL(string: "http://127.0.0.1:\(port)/v1/metrics")!,
    otlpLogsEndpoint: URL(string: "http://127.0.0.1:\(port)/v1/logs")!
  )
}
