import XCTest

@testable import TerraCore

final class TerraInstrumentationNameTests: XCTestCase {
  func testInstrumentationName_isStable() {
    XCTAssertEqual(Terra.instrumentationName, "io.opentelemetry.terra")
  }
}
