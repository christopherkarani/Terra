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

  func testDecodeRejectsMissingTerraSchemaAttributes() throws {
    let missing = try OTLPTestFixtures.serializedRequest(
      resourceAttributes: [
        "service.name": "demo-service",
        "service.version": "1.0.0",
        "terra.semantic.version": "v1",
        "terra.schema.family": "terra",
      ]
    )
    let decoder = OTLPRequestDecoder(
      maxBodyBytes: missing.count + 64,
      maxDecompressedBytes: missing.count + 64
    )

    XCTAssertThrowsError(try decoder.decode(body: missing, headers: ["Content-Encoding": "identity"])) { error in
      guard let error = error as? OTLPRequestDecoderError else {
        XCTFail("Expected OTLPRequestDecoderError, got \(error)")
        return
      }
      if case let .missingTerraSchemaAttributes(attributes) = error {
        XCTAssertTrue(attributes.contains("terra.runtime"))
        XCTAssertTrue(attributes.contains("terra.request.id"))
        XCTAssertTrue(attributes.contains("terra.session.id"))
        XCTAssertTrue(attributes.contains("terra.model.fingerprint"))
      } else {
        XCTFail("Expected missingTerraSchemaAttributes, got \(error)")
      }
    }
  }

  func testDecodeRejectsUnsupportedTerraSchemaVersion() throws {
    let unsupported = try OTLPTestFixtures.serializedRequest(
      resourceAttributes: [
        "service.name": "demo-service",
        "service.version": "1.0.0",
        "terra.semantic.version": "v2",
        "terra.schema.family": "terra",
        "terra.runtime": "http_api",
        "terra.request.id": "request-123",
        "terra.session.id": "session-456",
        "terra.model.fingerprint": "model:gpt-4o:quant:v1",
      ]
    )
    let decoder = OTLPRequestDecoder(
      maxBodyBytes: unsupported.count + 64,
      maxDecompressedBytes: unsupported.count + 64
    )

    XCTAssertThrowsError(
      try decoder.decode(body: unsupported, headers: ["Content-Encoding": "identity"])
    ) { error in
      guard let error = error as? OTLPRequestDecoderError else {
        XCTFail("Expected OTLPRequestDecoderError, got \(error)")
        return
      }
      switch error {
      case .unsupportedTerraSchema:
        break
      default:
        XCTFail("Expected unsupportedTerraSchema, got \(error)")
      }
    }
  }

  func testDecodePreservesNullSpanAttributes() throws {
    let body = try OTLPTestFixtures.serializedRequestWithNullSpanAttribute(
      key: "terra.optional.metric"
    )
    let decoder = OTLPRequestDecoder(
      maxBodyBytes: body.count + 64,
      maxDecompressedBytes: body.count + 64
    )

    let spans = try decoder.decode(body: body, headers: ["Content-Encoding": "identity"])
    let root = try XCTUnwrap(spans.first { $0.name == "root" })
    let value = root.attributes["terra.optional.metric"]
    guard case .null = value else {
      XCTFail("Expected .null for terra.optional.metric, got \(String(describing: value))")
      return
    }
  }

  func testDecodePreservesExtendedTerraMetadataAcrossSpanAndEvents() throws {
    var request = OTLPTestFixtures.makeExportRequest(resourceAttributes: OTLPTestFixtures.resourceAttributes)
    XCTAssertFalse(request.resourceSpans.isEmpty)
    XCTAssertFalse(request.resourceSpans[0].scopeSpans.isEmpty)
    XCTAssertFalse(request.resourceSpans[0].scopeSpans[0].spans.isEmpty)

    var root = request.resourceSpans[0].scopeSpans[0].spans[0]
    root.attributes.append(OTLPTestFixtures.makeKeyValue(key: "terra.runtime.confidence", doubleValue: 0.92))
    root.attributes.append(OTLPTestFixtures.makeKeyValue(key: "terra.control_loop.mode", stringValue: "closed_loop"))
    root.attributes.append(OTLPTestFixtures.makeKeyValue(key: "terra.event.aggregation_level", stringValue: "coalesced"))
    root.attributes.append(OTLPTestFixtures.makeKeyValue(key: "terra.policy.blocked", boolValue: false))
    root.attributes.append(OTLPTestFixtures.makeKeyValue(key: "terra.policy.reason", stringValue: "allowed"))
    root.attributes.append(OTLPTestFixtures.makeNullKeyValue(key: "terra.availability"))

    root.events.append(
      OTLPTestFixtures.makeEvent(
        name: "terra.recommendation",
        timeUnixNano: OTLPTestFixtures.rootStart + 1_000_000,
        attributes: [
          OTLPTestFixtures.makeKeyValue(key: "terra.recommendation.id", stringValue: "rec-001"),
          OTLPTestFixtures.makeKeyValue(key: "terra.recommendation.confidence", doubleValue: 0.87),
          OTLPTestFixtures.makeKeyValue(key: "terra.recommendation.action", stringValue: "reduce_batch_size"),
          OTLPTestFixtures.makeNullKeyValue(key: "terra.availability"),
        ]
      )
    )
    root.events.append(
      OTLPTestFixtures.makeEvent(
        name: "terra.anomaly.stalled_token",
        timeUnixNano: OTLPTestFixtures.rootStart + 2_000_000,
        attributes: [
          OTLPTestFixtures.makeKeyValue(key: "terra.anomaly.baseline_key", stringValue: "runtime:model"),
          OTLPTestFixtures.makeKeyValue(key: "terra.anomaly.score", doubleValue: 0.73),
        ]
      )
    )

    request.resourceSpans[0].scopeSpans[0].spans[0] = root

    let body = try request.serializedData()
    let decoder = OTLPRequestDecoder(
      maxBodyBytes: body.count + 64,
      maxDecompressedBytes: body.count + 64
    )

    let spans = try decoder.decode(body: body, headers: ["Content-Encoding": "identity"])
    let decodedRoot = try XCTUnwrap(spans.first { $0.name == "root" })

    XCTAssertEqual(decodedRoot.attributes[string: "terra.control_loop.mode"], "closed_loop")
    XCTAssertEqual(decodedRoot.attributes[string: "terra.event.aggregation_level"], "coalesced")
    XCTAssertEqual(decodedRoot.attributes["terra.policy.blocked"]?.boolValue, false)
    XCTAssertEqual(decodedRoot.attributes[string: "terra.policy.reason"], "allowed")

    let runtimeConfidence = try XCTUnwrap(decodedRoot.attributes["terra.runtime.confidence"]?.doubleValue)
    XCTAssertEqual(runtimeConfidence, 0.92, accuracy: 0.000_001)
    XCTAssertTrue(decodedRoot.attributes["terra.availability"]?.isNull == true)

    let recommendationEvent = try XCTUnwrap(decodedRoot.events.first { $0.name == "terra.recommendation" })
    XCTAssertEqual(
      recommendationEvent.attributes[string: "terra.recommendation.id"],
      "rec-001"
    )
    XCTAssertEqual(
      recommendationEvent.attributes[string: "terra.recommendation.action"],
      "reduce_batch_size"
    )
    let recommendationConfidence = try XCTUnwrap(
      recommendationEvent.attributes["terra.recommendation.confidence"]?.doubleValue
    )
    XCTAssertEqual(recommendationConfidence, 0.87, accuracy: 0.000_001)
    XCTAssertTrue(recommendationEvent.attributes["terra.availability"]?.isNull == true)

    let anomalyEvent = try XCTUnwrap(decodedRoot.events.first { $0.name == "terra.anomaly.stalled_token" })
    XCTAssertEqual(
      anomalyEvent.attributes[string: "terra.anomaly.baseline_key"],
      "runtime:model"
    )
    let anomalyScore = try XCTUnwrap(anomalyEvent.attributes["terra.anomaly.score"]?.doubleValue)
    XCTAssertEqual(anomalyScore, 0.73, accuracy: 0.000_001)
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
