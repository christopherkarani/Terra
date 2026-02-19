import OpenTelemetryApi
import OpenTelemetrySdk
@testable import Terra
import XCTest

final class TerraRuntimeInstallTests: XCTestCase {
  override func setUp() {
    super.setUp()
    Terra.install(.init())
  }

  override func tearDown() {
    Terra.install(.init())
    super.tearDown()
  }

  func testInstall_withoutProviders_clearsTracerAndLoggerOverrides() {
    let tracerProvider = TracerProviderSdk()
    let loggerProvider = LoggerProviderBuilder().build()

    Terra.install(
      .init(
        tracerProvider: tracerProvider,
        loggerProvider: loggerProvider,
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
