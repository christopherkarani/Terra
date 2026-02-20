import OpenTelemetrySdk
@testable import Terra
import XCTest

final class TerraOpenTelemetryDefaultsTests: XCTestCase {
  func testDefaultOtlpEndpoints_matchExpectedUrls() {
    XCTAssertEqual(
      Terra.defaultOtlpHttpTracesEndpoint().absoluteString,
      "http://localhost:4318/v1/traces"
    )
    XCTAssertEqual(
      Terra.defaultOtlpHttpMetricsEndpoint().absoluteString,
      "http://localhost:4318/v1/metrics"
    )
    XCTAssertEqual(
      Terra.defaultOtlpHttpLoggingEndpoint().absoluteString,
      "http://localhost:4318/v1/logs"
    )
  }

}

final class TerraRuntimeInstallTests: XCTestCase {
  func testInstallClearsOverridesWhenNil() {
    let tracerProvider = TracerProviderSdk()

    Terra.install(
      .init(tracerProvider: tracerProvider, registerProvidersAsGlobal: false)
    )

    let installed = Runtime.shared.tracerProvider as? TracerProviderSdk
    XCTAssertTrue(installed === tracerProvider)

    Terra.install(.init(registerProvidersAsGlobal: false))
    XCTAssertNil(Runtime.shared.tracerProvider)
  }
}
