import Foundation
import XCTest
@testable import TerraTraceKit

final class TreeRendererTests: XCTestCase {
  func testTreeRendererOrdersChildrenByStartTime() async throws {
    let decoder = OTLPRequestDecoder(maxBodyBytes: 1_000_000, maxDecompressedBytes: 1_000_000)
    let body = try OTLPTestFixtures.serializedSiblingRequest()
    let spans = try decoder.decode(body: body, headers: ["Content-Encoding": "identity"])

    let store = TraceStore(maxSpans: 50)
    _ = await store.ingest(spans)

    let snapshot = await store.snapshot(filter: nil)
    let renderer = TreeRenderer()
    let output = renderer.render(snapshot: snapshot)

    let expected = expectedTree(for: spans)
    XCTAssertEqual(output, expected)
  }

  func testTreeRendererReparentsWhenParentArrivesLater() async throws {
    let decoder = OTLPRequestDecoder(maxBodyBytes: 1_000_000, maxDecompressedBytes: 1_000_000)
    let body = try OTLPTestFixtures.serializedRequest()
    let spans = try decoder.decode(body: body, headers: ["Content-Encoding": "identity"])

    guard let root = spans.first(where: { $0.name == "root" }),
          let child = spans.first(where: { $0.name == "child" }) else {
      XCTFail("Missing expected spans")
      return
    }

    let store = TraceStore(maxSpans: 50)
    _ = await store.ingest([child])

    var snapshot = await store.snapshot(filter: nil)
    let renderer = TreeRenderer()
    let outputWithoutParent = renderer.render(snapshot: snapshot)

    let expectedWithoutParent = expectedTree(for: [child])
    XCTAssertEqual(outputWithoutParent, expectedWithoutParent)

    _ = await store.ingest([root])
    snapshot = await store.snapshot(filter: nil)

    let outputWithParent = renderer.render(snapshot: snapshot)
    let expectedWithParent = expectedTree(for: [root, child])
    XCTAssertEqual(outputWithParent, expectedWithParent)
  }

  func testTreeRendererRendersCycleInsteadOfDroppingTrace() throws {
    let traceID = try XCTUnwrap(TraceID(hex: "00000000000000000000000000000001"))
    let spanAID = try XCTUnwrap(SpanID(hex: "0000000000000001"))
    let spanBID = try XCTUnwrap(SpanID(hex: "0000000000000002"))

    let spanA = SpanRecord(
      traceID: traceID,
      spanID: spanAID,
      parentSpanID: spanBID,
      name: "span-a",
      kind: .internal,
      status: .ok,
      startTimeUnixNano: 1,
      endTimeUnixNano: 2,
      attributes: Attributes([]),
      resource: Resource(attributes: Attributes([]))
    )
    let spanB = SpanRecord(
      traceID: traceID,
      spanID: spanBID,
      parentSpanID: spanAID,
      name: "span-b",
      kind: .internal,
      status: .ok,
      startTimeUnixNano: 3,
      endTimeUnixNano: 4,
      attributes: Attributes([]),
      resource: Resource(attributes: Attributes([]))
    )

    let snapshot = TraceSnapshot(allSpans: [spanA, spanB], traces: [traceID: [spanA, spanB]])
    let output = TreeRenderer().render(snapshot: snapshot)

    XCTAssertTrue(output.contains("trace \(traceID.short)"))
    XCTAssertTrue(output.contains("[cycle]"), "Expected cycle marker in output: \(output)")
  }
}

private extension TreeRendererTests {
  func expectedTree(for spans: [SpanRecord]) -> String {
    guard let traceID = spans.first?.traceID else { return "" }

    let grouped = Dictionary(grouping: spans) { $0.traceID }
    guard let traceSpans = grouped[traceID] else { return "" }

    let nodes = Dictionary(uniqueKeysWithValues: traceSpans.map { ($0.spanID, $0) })
    let children = traceSpans.reduce(into: [SpanID: [SpanRecord]]()) { result, span in
      if let parent = span.parentSpanID {
        result[parent, default: []].append(span)
      }
    }

    let roots = traceSpans.filter { span in
      span.parentSpanID == nil || nodes[span.parentSpanID!] == nil
    }
    let sortedRoots = roots.sorted { $0.startTimeUnixNano < $1.startTimeUnixNano }

    var lines: [String] = ["trace \(traceID.short)"]
    for (index, root) in sortedRoots.enumerated() {
      let isLast = index == sortedRoots.count - 1
      appendLines(for: root, prefix: "", isLast: isLast, children: children, lines: &lines)
    }

    return lines.joined(separator: "\n")
  }

  func appendLines(
    for span: SpanRecord,
    prefix: String,
    isLast: Bool,
    children: [SpanID: [SpanRecord]],
    lines: inout [String]
  ) {
    let branch = isLast ? "\\-- " : "|-- "
    lines.append(prefix + branch + treeLine(for: span))

    let sortedChildren = (children[span.spanID] ?? [])
      .sorted { $0.startTimeUnixNano < $1.startTimeUnixNano }

    let childPrefix = prefix + (isLast ? "    " : "|   ")
    for (index, child) in sortedChildren.enumerated() {
      let childIsLast = index == sortedChildren.count - 1
      appendLines(for: child, prefix: childPrefix, isLast: childIsLast, children: children, lines: &lines)
    }
  }

  func treeLine(for span: SpanRecord) -> String {
    let duration = formatDuration(nanos: span.endTimeUnixNano - span.startTimeUnixNano)
    let attributes = span.attributes
      .map { key, value in (key, String(describing: value)) }
      .sorted { $0.0 < $1.0 }
      .map { "\($0.0)=\($0.1)" }

    var parts: [String] = [span.name, duration, span.spanID.short]
    parts.append(contentsOf: attributes)
    return parts.joined(separator: " ")
  }

  func formatDuration(nanos: UInt64) -> String {
    let ms = Double(nanos) / 1_000_000
    return String(format: "%.3fms", ms)
  }
}
