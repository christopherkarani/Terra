import Foundation
@testable import TerraTraceKit
import XCTest

final class StreamRendererTests: XCTestCase {
  func testStreamRendererProducesDeterministicLines() throws {
    let body = try OTLPTestFixtures.serializedRequest()
    let decoder = OTLPRequestDecoder(maxBodyBytes: 1_000_000, maxDecompressedBytes: 1_000_000)
    let spans = try decoder.decode(body: body, headers: ["Content-Encoding": "identity"])

    guard let root = spans.first(where: { $0.name == "root" }),
          let child = spans.first(where: { $0.name == "child" })
    else {
      XCTFail("Missing expected spans")
      return
    }

    let renderer = StreamRenderer()
    let output = renderer.render(spans: [child, root])

    let expected = [root, child]
      .sorted { $0.endTimeUnixNano < $1.endTimeUnixNano }
      .map { expectedLine(for: $0) }

    XCTAssertEqual(output, expected)
  }

  func testTelemetryPrivacyReadsSensitiveKeysFromSchemaViewerBehavior() throws {
    // The schema-driven predicate selects only privacy_sensitive_detail keys —
    // privacy_audit_detail entries are non-content state flags whose value is
    // itself the audit signal and must survive redaction (see P0-1).
    let schema = """
    {
      "registry": [
        {
          "key": "custom.secret",
          "viewer_behavior": "privacy_sensitive_detail"
        },
        {
          "key": "custom.audit",
          "viewer_behavior": "privacy_audit_detail"
        },
        {
          "key": "custom.public",
          "viewer_behavior": "span_detail"
        }
      ]
    }
    """
    let keys = try XCTUnwrap(TelemetryPrivacy.sensitiveKeys(fromSchemaData: Data(schema.utf8)))

    XCTAssertTrue(keys.contains("custom.secret"))
    XCTAssertFalse(keys.contains("custom.audit"))
    XCTAssertFalse(keys.contains("custom.public"))
  }

  func testStreamRendererRedactsSchemaSensitiveAttributes() throws {
    let traceID = try XCTUnwrap(TraceID(hex: OTLPTestFixtures.traceIDHex))
    let spanID = try XCTUnwrap(SpanID(hex: OTLPTestFixtures.parentSpanIDHex))
    let span = SpanRecord(
      traceID: traceID,
      spanID: spanID,
      parentSpanID: nil,
      name: "privacy",
      kind: .internal,
      status: .ok,
      startTimeUnixNano: 10,
      endTimeUnixNano: 20,
      attributes: Attributes(dictionary: [
        "gen_ai.prompt.content": .string("secret prompt"),
        "gen_ai.request.model": .string("gpt-test"),
        "terra.prompt.sha256": .string("prompt-digest"),
        "terra.safety.subject.sha256": .string("safety-digest"),
      ]),
      resource: Resource(attributes: Attributes([]))
    )

    let output = StreamRenderer().render(spans: [span]).joined(separator: "\n")

    XCTAssertFalse(output.contains("secret prompt"))
    XCTAssertFalse(output.contains("prompt-digest"))
    XCTAssertFalse(output.contains("safety-digest"))
    XCTAssertTrue(output.contains("gen_ai.prompt.content=[redacted: privacy-sensitive]"))
    XCTAssertTrue(output.contains("terra.prompt.sha256=[redacted: privacy-sensitive]"))
    XCTAssertTrue(output.contains("terra.safety.subject.sha256=[redacted: privacy-sensitive]"))
    XCTAssertTrue(output.contains("gen_ai.request.model=gpt-test"))
  }
}

private extension StreamRendererTests {
  func expectedLine(for span: SpanRecord) -> String {
    let timestamp = formatTimestamp(nanos: span.endTimeUnixNano)
    let duration = formatDuration(nanos: span.endTimeUnixNano - span.startTimeUnixNano)
    let attributes = span.attributes
      .map { key, value in (key, String(describing: value)) }
      .sorted { $0.0 < $1.0 }
      .map { "\($0.0)=\($0.1)" }

    var parts: [String] = [timestamp, duration, span.name, span.traceID.short, span.spanID.short]
    parts.append(contentsOf: attributes)
    return parts.joined(separator: " ")
  }

  func formatTimestamp(nanos: UInt64) -> String {
    guard nanos > 0 else { return "0" }
    let seconds = Double(nanos) / 1_000_000_000
    let date = Date(timeIntervalSince1970: seconds)
    return makeTimestampFormatter().string(from: date)
  }

  func formatDuration(nanos: UInt64) -> String {
    let ms = Double(nanos) / 1_000_000
    return String(format: "%.3fms", ms)
  }
}

private func makeTimestampFormatter() -> ISO8601DateFormatter {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  formatter.timeZone = TimeZone(secondsFromGMT: 0)
  return formatter
}
