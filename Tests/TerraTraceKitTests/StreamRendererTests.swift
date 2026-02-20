import Foundation
import XCTest
@testable import TerraTraceKit

final class StreamRendererTests: XCTestCase {
  func testStreamRendererProducesDeterministicLines() throws {
    let body = try OTLPTestFixtures.serializedRequest()
    let decoder = OTLPRequestDecoder(maxBodyBytes: 1_000_000, maxDecompressedBytes: 1_000_000)
    let spans = try decoder.decode(body: body, headers: ["Content-Encoding": "identity"])

    guard let root = spans.first(where: { $0.name == "root" }),
          let child = spans.first(where: { $0.name == "child" }) else {
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
