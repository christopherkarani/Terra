import OpenTelemetryApi
import XCTest

@testable import Terra

final class TerraOpenTelemetryInstallRollbackTests: XCTestCase {
  override func setUp() {
    super.setUp()
    Terra.resetOpenTelemetryForTesting()
  }

  override func tearDown() {
    Terra.resetOpenTelemetryForTesting()
    super.tearDown()
  }

  func testInstallFailure_rollsBackGlobalProviders_andAllowsRetry() throws {
    let previousTracer = OpenTelemetry.instance.tracerProvider
    let previousMeter = OpenTelemetry.instance.meterProvider
    let previousLogger = OpenTelemetry.instance.loggerProvider

    let storageURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("terra-install-rollback-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)

    let tracesPath = storageURL.appendingPathComponent("traces", isDirectory: false)
    XCTAssertTrue(FileManager.default.createFile(atPath: tracesPath.path, contents: Data()))

    let failingConfiguration = Terra.OpenTelemetryConfiguration(
      enableTraces: true,
      enableMetrics: true,
      enableLogs: true,
      enableSignposts: false,
      enableSessions: false,
      persistence: .init(storageURL: storageURL)
    )

    XCTAssertThrowsError(try Terra.installOpenTelemetry(failingConfiguration))

    XCTAssertTrue(isSameInstance(OpenTelemetry.instance.tracerProvider, previousTracer))
    XCTAssertTrue(isSameInstance(OpenTelemetry.instance.meterProvider, previousMeter))
    XCTAssertTrue(isSameInstance(OpenTelemetry.instance.loggerProvider, previousLogger))

    let retryStorageURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("terra-install-retry-\(UUID().uuidString)", isDirectory: true)

    let retryConfiguration = Terra.OpenTelemetryConfiguration(
      enableTraces: true,
      enableMetrics: true,
      enableLogs: true,
      enableSignposts: false,
      enableSessions: false,
      persistence: .init(storageURL: retryStorageURL)
    )

    XCTAssertNoThrow(try Terra.installOpenTelemetry(retryConfiguration))
  }

  private func isSameInstance<T>(_ lhs: T, _ rhs: T) -> Bool {
    ObjectIdentifier(lhs as AnyObject) == ObjectIdentifier(rhs as AnyObject)
  }
}
