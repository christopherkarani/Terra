import OpenTelemetrySdk
import XCTest

@testable import TerraCore

final class TerraRuntimeInstallTests: XCTestCase {
  func testInstall_clearsProviderOverridesWhenNil() {
    let tracerProvider = TracerProviderSdk()
    let loggerProvider = LoggerProviderSdk()

    Terra.install(
      .init(
        tracerProvider: tracerProvider,
        loggerProvider: loggerProvider,
        registerProvidersAsGlobal: false
      )
    )

    XCTAssertNotNil(Runtime.shared.tracerProvider)
    XCTAssertNotNil(Runtime.shared.loggerProvider)

    Terra.install(.init(tracerProvider: nil, loggerProvider: nil, registerProvidersAsGlobal: false))

    XCTAssertNil(Runtime.shared.tracerProvider)
    XCTAssertNil(Runtime.shared.loggerProvider)
  }
}
