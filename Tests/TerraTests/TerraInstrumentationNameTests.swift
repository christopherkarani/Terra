import XCTest

@testable import Terra

final class TerraInstrumentationNameTests: XCTestCase {
  func testInstrumentationName_isStable() {
    XCTAssertEqual(Terra.instrumentationName, "io.opentelemetry.terra")
  }
}
