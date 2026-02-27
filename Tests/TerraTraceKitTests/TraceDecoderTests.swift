import XCTest
@testable import TerraTraceKit

final class TraceDecoderTests: XCTestCase {
  func testDecodeSpans_requiresTrailingCommaFormat() {
    let decoder = TraceDecoder()
    let input = Data("[]".utf8)

    XCTAssertThrowsError(try decoder.decodeSpans(from: input)) { error in
      guard case TraceDecodingError.invalidFormat = error else {
        XCTFail("Expected invalidFormat, got \(error)")
        return
      }
    }
  }

  func testDecodeSpans_reportsInvalidFormatForMalformedPayload() {
    let decoder = TraceDecoder()
    let input = Data("not-json,".utf8)

    XCTAssertThrowsError(try decoder.decodeSpans(from: input)) { error in
      guard case TraceDecodingError.invalidFormat = error else {
        XCTFail("Expected invalidFormat, got \(error)")
        return
      }
    }
  }
}
