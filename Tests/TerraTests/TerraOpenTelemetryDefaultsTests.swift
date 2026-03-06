import XCTest

@testable import TerraCore

final class TerraOpenTelemetryDefaultsTests: XCTestCase {
  func testDefaultOtlpHttpEndpoints() {
    XCTAssertEqual(
      Terra.defaultOtlpHttpTracesEndpoint().absoluteString,
      "http://localhost:4318/v1/traces"
    )
    XCTAssertEqual(
      Terra.defaultOtlpHttpMetricsEndpoint().absoluteString,
      "http://localhost:4318/v1/metrics"
    )
    XCTAssertEqual(
      Terra.defaultOtlpHttpLogsEndpoint().absoluteString,
      "http://localhost:4318/v1/logs"
    )
  }
}
