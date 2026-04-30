@testable import TerraTraceKit
import XCTest

#if canImport(OpenTelemetryProtocolExporterCommon)
  import OpenTelemetryProtocolExporterCommon
#elseif canImport(OpenTelemetryProtocolExporterGrpc)
  import OpenTelemetryProtocolExporterGrpc
#elseif canImport(OpenTelemetryProtocolExporterHttp)
  import OpenTelemetryProtocolExporterHttp
#elseif canImport(OpenTelemetryProtocolExporterHTTP)
  import OpenTelemetryProtocolExporterHTTP
#endif

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

  func testDecodeRejectsWhenSpanCountExceedsLimit() throws {
    let request = makeRequestWithSpanCount(3)
    let body = try request.serializedData()
    let decoder = OTLPRequestDecoder(
      limits: .init(
        maxBodyBytes: body.count + 64,
        maxDecompressedBytes: body.count + 64,
        maxSpansPerRequest: 2,
        maxAttributesPerSpan: 256,
        maxAnyValueDepth: 8
      )
    )

    XCTAssertThrowsError(
      try decoder.decode(body: body, headers: ["Content-Encoding": "identity"])
    )
  }

  func testDecodeRejectsWhenAttributesPerSpanExceedLimit() throws {
    var request = OTLPTestFixtures.makeExportRequest()
    guard var firstScope = request.resourceSpans.first?.scopeSpans.first else {
      XCTFail("Missing scope spans")
      return
    }
    guard var firstSpan = firstScope.spans.first else {
      XCTFail("Missing span")
      return
    }

    firstSpan.attributes = (0 ..< 3).map { index in
      OTLPTestFixtures.makeKeyValue(key: "attr-\(index)", stringValue: "value-\(index)")
    }
    firstScope.spans[0] = firstSpan
    request.resourceSpans[0].scopeSpans[0] = firstScope

    let body = try request.serializedData()
    let decoder = OTLPRequestDecoder(
      limits: .init(
        maxBodyBytes: body.count + 64,
        maxDecompressedBytes: body.count + 64,
        maxSpansPerRequest: 10,
        maxAttributesPerSpan: 2,
        maxAnyValueDepth: 8
      )
    )

    XCTAssertThrowsError(
      try decoder.decode(body: body, headers: ["Content-Encoding": "identity"])
    )
  }

  func testDecodeRejectsWhenResourceAttributesExceedLimit() throws {
    var request = OTLPTestFixtures.makeExportRequest()
    request.resourceSpans[0].resource.attributes = (0 ..< 3).map { index in
      OTLPTestFixtures.makeKeyValue(key: "resource-\(index)", stringValue: "value-\(index)")
    }

    let body = try request.serializedData()
    let decoder = OTLPRequestDecoder(
      limits: .init(
        maxBodyBytes: body.count + 64,
        maxDecompressedBytes: body.count + 64,
        maxAttributesPerResource: 2
      )
    )

    XCTAssertThrowsError(
      try decoder.decode(body: body, headers: ["Content-Encoding": "identity"])
    )
  }

  func testDecodeRejectsWhenAnyValueNestingExceedsLimit() throws {
    var request = OTLPTestFixtures.makeExportRequest()
    guard var firstScope = request.resourceSpans.first?.scopeSpans.first else {
      XCTFail("Missing scope spans")
      return
    }
    guard var firstSpan = firstScope.spans.first else {
      XCTFail("Missing span")
      return
    }

    var nestedValue = Opentelemetry_Proto_Common_V1_AnyValue()
    nestedValue.arrayValue.values = [makeNestedArrayAnyValue(depth: 3)]
    var nestedAttr = Opentelemetry_Proto_Common_V1_KeyValue()
    nestedAttr.key = "too.deep"
    nestedAttr.value = nestedValue
    firstSpan.attributes.append(nestedAttr)
    firstScope.spans[0] = firstSpan
    request.resourceSpans[0].scopeSpans[0] = firstScope

    let body = try request.serializedData()
    let decoder = OTLPRequestDecoder(
      limits: .init(
        maxBodyBytes: body.count + 64,
        maxDecompressedBytes: body.count + 64,
        maxSpansPerRequest: 10,
        maxAttributesPerSpan: 256,
        maxAnyValueDepth: 2
      )
    )

    XCTAssertThrowsError(
      try decoder.decode(body: body, headers: ["Content-Encoding": "identity"])
    )
  }

  func testDecodePreservesEventsLinksStatusDescriptionAndDroppedCounts() throws {
    var request = OTLPTestFixtures.makeExportRequest()
    var scope = request.resourceSpans[0].scopeSpans[0]
    var root = scope.spans[0]

    root.status.code = .error
    root.status.message = "model returned partial output"
    root.droppedAttributesCount = 1
    root.droppedEventsCount = 2
    root.droppedLinksCount = 3

    var event = Opentelemetry_Proto_Trace_V1_Span.Event()
    event.name = "terra.first_token"
    event.timeUnixNano = OTLPTestFixtures.childStart
    event.attributes = [
      OTLPTestFixtures.makeKeyValue(key: "terra.stream.chunk_count", stringValue: "1"),
    ]
    event.droppedAttributesCount = 4
    root.events = [event]

    var link = Opentelemetry_Proto_Trace_V1_Span.Link()
    link.traceID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".hexBytesForTraceKitTests()
    link.spanID = "bbbbbbbbbbbbbbbb".hexBytesForTraceKitTests()
    link.traceState = "rojo=00f067aa0ba902b7"
    link.attributes = [
      OTLPTestFixtures.makeKeyValue(key: "link.kind", stringValue: "causal"),
    ]
    link.droppedAttributesCount = 5
    root.links = [link]

    scope.spans[0] = root
    request.resourceSpans[0].scopeSpans[0] = scope

    let body = try request.serializedData()
    let decoder = OTLPRequestDecoder(
      limits: .init(maxBodyBytes: body.count + 64, maxDecompressedBytes: body.count + 64)
    )

    let spans = try decoder.decode(body: body, headers: ["Content-Encoding": "identity"])
    let decodedRoot = try XCTUnwrap(spans.first(where: { $0.name == "root" }))

    XCTAssertEqual(decodedRoot.status, .error)
    XCTAssertEqual(decodedRoot.statusDescription, "model returned partial output")
    XCTAssertEqual(decodedRoot.droppedAttributesCount, 1)
    XCTAssertEqual(decodedRoot.droppedEventsCount, 2)
    XCTAssertEqual(decodedRoot.droppedLinksCount, 3)
    XCTAssertEqual(decodedRoot.events.count, 1)
    XCTAssertEqual(decodedRoot.events[0].name, "terra.first_token")
    XCTAssertEqual(decodedRoot.events[0].timeUnixNano, OTLPTestFixtures.childStart)
    XCTAssertEqual(decodedRoot.events[0].attributes[string: "terra.stream.chunk_count"], "1")
    XCTAssertEqual(decodedRoot.events[0].droppedAttributesCount, 4)
    XCTAssertEqual(decodedRoot.links.count, 1)
    XCTAssertEqual(decodedRoot.links[0].traceID.hex, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    XCTAssertEqual(decodedRoot.links[0].spanID.hex, "bbbbbbbbbbbbbbbb")
    XCTAssertEqual(decodedRoot.links[0].traceState, "rojo=00f067aa0ba902b7")
    XCTAssertEqual(decodedRoot.links[0].attributes[string: "link.kind"], "causal")
    XCTAssertEqual(decodedRoot.links[0].droppedAttributesCount, 5)
  }

  #if canImport(Compression)
    func testDecodeRejectsGzipWithCorruptCRC() throws {
      let body = try OTLPTestFixtures.serializedRequest()
      var compressed = try OTLPTestCompression.gzip(body)
      compressed[compressed.count - 8] ^= 0xFF
      let decoder = OTLPRequestDecoder(
        maxBodyBytes: compressed.count + 64,
        maxDecompressedBytes: body.count + 64
      )

      XCTAssertThrowsError(
        try decoder.decode(body: compressed, headers: ["Content-Encoding": "gzip"])
      )
    }

    func testDecodeRejectsGzipWithCorruptISIZE() throws {
      let body = try OTLPTestFixtures.serializedRequest()
      var compressed = try OTLPTestCompression.gzip(body)
      compressed[compressed.count - 4] ^= 0xFF
      let decoder = OTLPRequestDecoder(
        maxBodyBytes: compressed.count + 64,
        maxDecompressedBytes: body.count + 64
      )

      XCTAssertThrowsError(
        try decoder.decode(body: compressed, headers: ["Content-Encoding": "gzip"])
      )
    }
  #endif
}

private extension String {
  func hexBytesForTraceKitTests() -> Data {
    var data = Data()
    var index = startIndex
    while index < endIndex {
      let nextIndex = self.index(index, offsetBy: 2)
      let byteString = self[index ..< nextIndex]
      if let byte = UInt8(byteString, radix: 16) {
        data.append(byte)
      }
      index = nextIndex
    }
    return data
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

  func makeRequestWithSpanCount(_ spanCount: Int) -> Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest {
    var request = OTLPTestFixtures.makeExportRequest()
    guard spanCount > 0 else { return request }
    guard var scope = request.resourceSpans.first?.scopeSpans.first else { return request }
    guard let template = scope.spans.first else { return request }

    var spans: [Opentelemetry_Proto_Trace_V1_Span] = []
    spans.reserveCapacity(spanCount)
    for index in 0 ..< spanCount {
      var span = template
      span.name = "span-\(index)"
      span.spanID = Data(repeating: UInt8((index + 1) % 255), count: 8)
      spans.append(span)
    }
    scope.spans = spans
    request.resourceSpans[0].scopeSpans[0] = scope
    return request
  }

  func makeNestedArrayAnyValue(depth: Int) -> Opentelemetry_Proto_Common_V1_AnyValue {
    if depth <= 0 {
      var leaf = Opentelemetry_Proto_Common_V1_AnyValue()
      leaf.stringValue = "leaf"
      return leaf
    }
    var value = Opentelemetry_Proto_Common_V1_AnyValue()
    value.arrayValue.values = [makeNestedArrayAnyValue(depth: depth - 1)]
    return value
  }
}
