import XCTest
@testable import TerraTraceKit

final class OTLPRequestDecoderTests: XCTestCase {
  func testDecodeIdentityPayloadReturnsExpectedSpans() throws {
    let body = try OTLPTestFixtures.serializedRequest()
    let decoder = OTLPRequestDecoder(
      maxBodyBytes: body.count + 64,
      maxDecompressedBytes: body.count + 64
    )

    let spans = try decoder.decode(body: body, headers: ["Content-Encoding": "identity"])

    assertDecodedSpans(spans)
  }

  #if canImport(Compression)
  func testDecodeGzipPayloadReturnsExpectedSpans() throws {
    let body = try OTLPTestFixtures.serializedRequest()
    let compressed = try OTLPTestCompression.gzip(body)
    let decoder = OTLPRequestDecoder(
      maxBodyBytes: compressed.count + 64,
      maxDecompressedBytes: body.count + 64
    )

    let spans = try decoder.decode(body: compressed, headers: ["Content-Encoding": "gzip"])

    assertDecodedSpans(spans)
  }

  func testDecodeDeflatePayloadReturnsExpectedSpans() throws {
    let body = try OTLPTestFixtures.serializedRequest()
    let compressed = try OTLPTestCompression.deflate(body)
    let decoder = OTLPRequestDecoder(
      maxBodyBytes: compressed.count + 64,
      maxDecompressedBytes: body.count + 64
    )

    let spans = try decoder.decode(body: compressed, headers: ["Content-Encoding": "deflate"])

    assertDecodedSpans(spans)
  }
  #endif

  func testDecodeRejectsOversizedDecompressedPayload() throws {
    let body = try OTLPTestFixtures.serializedRequest()
    let decoder = OTLPRequestDecoder(
      maxBodyBytes: body.count + 64,
      maxDecompressedBytes: body.count - 1
    )

    XCTAssertThrowsError(
      try decoder.decode(body: body, headers: ["Content-Encoding": "identity"])
    )
  }
}

private extension OTLPRequestDecoderTests {
  func assertDecodedSpans(_ spans: [SpanRecord], file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(spans.count, 2, file: file, line: line)

    guard let root = spans.first(where: { $0.name == "root" }) else {
      XCTFail("Missing root span", file: file, line: line)
      return
    }
    guard let child = spans.first(where: { $0.name == "child" }) else {
      XCTFail("Missing child span", file: file, line: line)
      return
    }

    XCTAssertEqual(root.traceID.hex, OTLPTestFixtures.traceIDHex, file: file, line: line)
    XCTAssertEqual(root.spanID.hex, OTLPTestFixtures.parentSpanIDHex, file: file, line: line)
    XCTAssertNil(root.parentSpanID, file: file, line: line)
    XCTAssertEqual(root.kind, .server, file: file, line: line)
    XCTAssertEqual(root.status, .ok, file: file, line: line)
    XCTAssertEqual(root.startTimeUnixNano, OTLPTestFixtures.rootStart, file: file, line: line)
    XCTAssertEqual(root.endTimeUnixNano, OTLPTestFixtures.rootEnd, file: file, line: line)
    XCTAssertEqual(root.attributes[string: "gen_ai.model"], "gpt-4o", file: file, line: line)
    XCTAssertEqual(root.resourceAttributes[string: "service.name"], "demo-service", file: file, line: line)

    XCTAssertEqual(child.traceID.hex, OTLPTestFixtures.traceIDHex, file: file, line: line)
    XCTAssertEqual(child.parentSpanID?.hex, OTLPTestFixtures.parentSpanIDHex, file: file, line: line)
    XCTAssertEqual(child.spanID.hex, OTLPTestFixtures.childSpanIDHex, file: file, line: line)
    XCTAssertEqual(child.kind, .client, file: file, line: line)
    XCTAssertEqual(child.status, .ok, file: file, line: line)
    XCTAssertEqual(child.startTimeUnixNano, OTLPTestFixtures.childStart, file: file, line: line)
    XCTAssertEqual(child.endTimeUnixNano, OTLPTestFixtures.childEnd, file: file, line: line)
    XCTAssertEqual(child.attributes[string: "gen_ai.operation"], "chat", file: file, line: line)
    XCTAssertEqual(child.resourceAttributes[string: "service.name"], "demo-service", file: file, line: line)
  }
}
