import OpenTelemetryApi
@testable import Terra
import XCTest

final class TerraRuntimeInstallTests: XCTestCase {
  override func tearDown() {
    Terra.install(.init(registerProvidersAsGlobal: false))
    super.tearDown()
  }

  func testInstall_withNilProviders_clearsRuntimeOverrides() {
    Terra.install(
      .init(
        tracerProvider: OpenTelemetry.instance.tracerProvider,
        loggerProvider: OpenTelemetry.instance.loggerProvider,
        registerProvidersAsGlobal: false
      )
    )

    XCTAssertNotNil(Runtime.shared.tracerProvider)
    XCTAssertNotNil(Runtime.shared.loggerProvider)

    Terra.install(.init(registerProvidersAsGlobal: false))

    XCTAssertNil(Runtime.shared.tracerProvider)
    XCTAssertNil(Runtime.shared.loggerProvider)
  }
}
