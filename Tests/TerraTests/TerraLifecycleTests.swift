import XCTest
@testable import TerraCore

final class TerraLifecycleTests: XCTestCase {

  override func setUp() async throws {
    // Reset both the OTel install state and the Runtime lifecycle state before each test.
    Terra.resetOpenTelemetryForTesting()
  }

  override func tearDown() async throws {
    // Shut down if anything was installed during the test.
    Terra._shutdownOpenTelemetry()
  }

  // MARK: - State Query Tests

  func testInitialState_isStopped() {
    XCTAssertEqual(Terra._lifecycleState, .stopped)
    XCTAssertFalse(Terra._isRunning)
  }

  func testAfterInstall_isRunning() throws {
    let config = minimalConfig()
    try Terra.installOpenTelemetry(config)
    XCTAssertEqual(Terra._lifecycleState, .running)
    XCTAssertTrue(Terra._isRunning)
  }

  func testAfterShutdown_isStopped() async throws {
    try Terra.installOpenTelemetry(minimalConfig())
    XCTAssertTrue(Terra._isRunning)

    Terra._shutdownOpenTelemetry()

    XCTAssertEqual(Terra._lifecycleState, .stopped)
    XCTAssertFalse(Terra._isRunning)
  }

  func testShutdown_whenNotRunning_isIdempotent() async {
    XCTAssertFalse(Terra._isRunning)
    Terra._shutdownOpenTelemetry()  // no-op: must not crash
    Terra._shutdownOpenTelemetry()  // second call: must not crash
    XCTAssertFalse(Terra._isRunning)
  }

  func testShutdown_isIdempotent_afterInstall() async throws {
    try Terra.installOpenTelemetry(minimalConfig())
    Terra._shutdownOpenTelemetry()
    Terra._shutdownOpenTelemetry()  // second call: must not crash
    XCTAssertFalse(Terra._isRunning)
  }

  func testStartAfterShutdown_succeeds() async throws {
    let config1 = minimalConfig(port: 14001)
    let config2 = minimalConfig(port: 14002)

    try Terra.installOpenTelemetry(config1)
    XCTAssertTrue(Terra._isRunning)

    Terra._shutdownOpenTelemetry()
    XCTAssertFalse(Terra._isRunning)

    // Must succeed — state is stopped after shutdown
    XCTAssertNoThrow(try Terra.installOpenTelemetry(config2))
    XCTAssertTrue(Terra._isRunning)
  }

  func testStartSameConfig_isIdempotent() throws {
    let config = minimalConfig()
    try Terra.installOpenTelemetry(config)
    // Second call with identical config: no throw, stays running
    XCTAssertNoThrow(try Terra.installOpenTelemetry(config))
    XCTAssertTrue(Terra._isRunning)
  }

  func testStartDifferentConfig_throwsAlreadyInstalled() throws {
    let config1 = minimalConfig(port: 14001)
    let config2 = minimalConfig(port: 14002)
    try Terra.installOpenTelemetry(config1)
    XCTAssertThrowsError(try Terra.installOpenTelemetry(config2)) { error in
      XCTAssertEqual(error as? Terra.InstallOpenTelemetryError, .alreadyInstalled)
    }
  }

  func testShutdown_withAugmentExistingStrategy_leavesStateStopped() async throws {
    // .augmentExisting borrows the existing global provider; Terra must not
    // call shutdown() on it, but must still transition its own lifecycle state.
    var config = minimalConfig()
    // We can't easily verify the borrowed provider is not shut down without
    // deeper OTel SDK inspection, so we assert the lifecycle contract:
    // after shutdown Terra is .stopped and a fresh install is allowed.
    config = Terra.OpenTelemetryConfiguration(
      tracerProviderStrategy: .augmentExisting,
      enableTraces: false,
      enableMetrics: false,
      enableLogs: false,
      enableSignposts: false,
      enableSessions: false,
      otlpTracesEndpoint: URL(string: "http://127.0.0.1:14098/v1/traces")!,
      otlpMetricsEndpoint: URL(string: "http://127.0.0.1:14098/v1/metrics")!,
      otlpLogsEndpoint: URL(string: "http://127.0.0.1:14098/v1/logs")!
    )

    XCTAssertNoThrow(try Terra.installOpenTelemetry(config))
    XCTAssertTrue(Terra._isRunning)

    Terra._shutdownOpenTelemetry()

    XCTAssertFalse(Terra._isRunning)
    XCTAssertEqual(Terra._lifecycleState, .stopped)

    // Fresh install must succeed after augmentExisting shutdown
    XCTAssertNoThrow(try Terra.installOpenTelemetry(minimalConfig(port: 14097)))
    XCTAssertTrue(Terra._isRunning)
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
