#if canImport(OpenTelemetryProtocolExporterCommon)
import OpenTelemetryProtocolExporterCommon
#elseif canImport(OpenTelemetryProtocolExporterGrpc)
import OpenTelemetryProtocolExporterGrpc
#elseif canImport(OpenTelemetryProtocolExporterHttp)
import OpenTelemetryProtocolExporterHttp
#elseif canImport(OpenTelemetryProtocolExporterHTTP)
import OpenTelemetryProtocolExporterHTTP
#else
#error("OpenTelemetry OTLP protobuf module not available")
#endif
import SwiftProtobuf
import XCTest
@testable import TerraTraceKit

final class TraceStoreTests: XCTestCase {
  func testIngestSnapshotGroupsByTraceID() async throws {
    let decoder = OTLPRequestDecoder(maxBodyBytes: 1_000_000, maxDecompressedBytes: 1_000_000)
    let primaryBody = try OTLPTestFixtures.serializedRequest()
    let primarySpans = try decoder.decode(body: primaryBody, headers: ["Content-Encoding": "identity"])

    let secondaryRequest = makeSecondaryRequest()
    let secondaryBody = try secondaryRequest.serializedData()
    let secondarySpans = try decoder.decode(body: secondaryBody, headers: ["Content-Encoding": "identity"])

    let store = TraceStore(maxSpans: 50)
    _ = await store.ingest(primarySpans)
    _ = await store.ingest(secondarySpans)

    let snapshot = await store.snapshot(filter: nil)

    XCTAssertEqual(snapshot.allSpans.count, primarySpans.count + secondarySpans.count)
    XCTAssertEqual(snapshot.traces.count, 2)
    XCTAssertEqual(snapshot.traces[primarySpans[0].traceID]?.count, primarySpans.count)
    XCTAssertEqual(snapshot.traces[secondarySpans[0].traceID]?.count, secondarySpans.count)
  }

  func testSnapshotFiltersByNamePrefixAndTraceID() async throws {
    let decoder = OTLPRequestDecoder(maxBodyBytes: 1_000_000, maxDecompressedBytes: 1_000_000)
    let primaryBody = try OTLPTestFixtures.serializedRequest()
    let primarySpans = try decoder.decode(body: primaryBody, headers: ["Content-Encoding": "identity"])

    let secondaryRequest = makeSecondaryRequest()
    let secondaryBody = try secondaryRequest.serializedData()
    let secondarySpans = try decoder.decode(body: secondaryBody, headers: ["Content-Encoding": "identity"])

    let store = TraceStore(maxSpans: 50)
    _ = await store.ingest(primarySpans)
    _ = await store.ingest(secondarySpans)

    let nameFilter = TraceFilter(traceID: nil, namePrefix: "root")
    let nameSnapshot = await store.snapshot(filter: nameFilter)
    XCTAssertTrue(nameSnapshot.allSpans.allSatisfy { $0.name.hasPrefix("root") })

    let traceFilter = TraceFilter(traceID: primarySpans[0].traceID, namePrefix: nil)
    let traceSnapshot = await store.snapshot(filter: traceFilter)
    XCTAssertEqual(traceSnapshot.traces.count, 1)
    XCTAssertEqual(traceSnapshot.traces[primarySpans[0].traceID]?.count, primarySpans.count)
  }

  func testTraceStoreEvictionDoesNotOrphanCurrentTrace() async throws {
    // Build three traces (A, B, C) with two spans each, total 6 spans.
    // maxSpans = 4 forces eviction. Eviction must remove an entire trace's
    // spans together rather than orphaning one half of a parent/child pair.
    let traceA = try XCTUnwrap(TraceID(hex: "11111111111111111111111111111111"))
    let traceB = try XCTUnwrap(TraceID(hex: "22222222222222222222222222222222"))
    let traceC = try XCTUnwrap(TraceID(hex: "33333333333333333333333333333333"))

    let aRoot = makeP113Span(traceID: traceA, spanIDHex: "a000000000000001", name: "a-root")
    let aChild = makeP113Span(traceID: traceA, spanIDHex: "a000000000000002", name: "a-child")
    let bRoot = makeP113Span(traceID: traceB, spanIDHex: "b000000000000001", name: "b-root")
    let bChild = makeP113Span(traceID: traceB, spanIDHex: "b000000000000002", name: "b-child")
    let cRoot = makeP113Span(traceID: traceC, spanIDHex: "c000000000000001", name: "c-root")
    let cChild = makeP113Span(traceID: traceC, spanIDHex: "c000000000000002", name: "c-child")

    let store = TraceStore(maxSpans: 4)
    _ = await store.ingest([aRoot, aChild])
    _ = await store.ingest([bRoot, bChild])
    _ = await store.ingest([cRoot, cChild])

    let snapshot = await store.snapshot(filter: nil)
    XCTAssertLessThanOrEqual(snapshot.allSpans.count, 4)

    // Each trace that survives must still have BOTH of its spans (no orphans).
    for (traceID, spans) in snapshot.traces {
      XCTAssertEqual(
        spans.count,
        2,
        "Trace \(traceID.hex) was partially evicted (\(spans.count)/2)"
      )
    }

    // The most-recent trace (C) must always be retained whole because eviction
    // prefers older traces.
    XCTAssertEqual(snapshot.traces[traceC]?.count, 2, "Most recent trace C must survive intact")
  }

  func testIngestReplacesDuplicateSpanWithRicherRecord() async throws {
    let traceID = try XCTUnwrap(TraceID(hex: OTLPTestFixtures.traceIDHex))
    let spanID = try XCTUnwrap(SpanID(hex: OTLPTestFixtures.parentSpanIDHex))
    let partial = makeSpanRecord(
      traceID: traceID,
      spanID: spanID,
      name: "in-flight",
      status: .unset,
      end: 0
    )
    let richer = makeSpanRecord(
      traceID: traceID,
      spanID: spanID,
      name: "completed",
      status: .ok,
      end: 20,
      attributes: Attributes(dictionary: ["gen_ai.request.model": .string("gpt-test")]),
      events: [
        SpanEventRecord(
          name: "terra.first_token",
          timeUnixNano: 12,
          attributes: Attributes(dictionary: ["terra.stream.output_tokens": .int(1)])
        )
      ]
    )

    let store = TraceStore(maxSpans: 50)
    let firstAccepted = await store.ingest([partial])
    let secondAccepted = await store.ingest([richer])
    let thirdAccepted = await store.ingest([partial])

    XCTAssertEqual(firstAccepted, [partial])
    XCTAssertEqual(secondAccepted, [richer])
    XCTAssertTrue(thirdAccepted.isEmpty)

    let snapshot = await store.snapshot(filter: nil)
    XCTAssertEqual(snapshot.allSpans.count, 1)
    let stored = try XCTUnwrap(snapshot.allSpans.first)
    XCTAssertEqual(stored.name, "completed")
    XCTAssertEqual(stored.status, .ok)
    XCTAssertEqual(stored.endTimeUnixNano, 20)
    XCTAssertEqual(stored.attributes["gen_ai.request.model"], .string("gpt-test"))
    XCTAssertEqual(stored.events.count, 1)
  }
}

private extension TraceStoreTests {
  func makeP113Span(
    traceID: TraceID,
    spanIDHex: String,
    name: String
  ) -> SpanRecord {
    let spanID = SpanID(hex: spanIDHex) ?? SpanID(hex: "0000000000000001")!
    return SpanRecord(
      traceID: traceID,
      spanID: spanID,
      parentSpanID: nil,
      name: name,
      kind: .internal,
      status: .ok,
      startTimeUnixNano: 1,
      endTimeUnixNano: 2,
      attributes: Attributes([]),
      resource: Resource(attributes: Attributes([]))
    )
  }

  func makeSpanRecord(
    traceID: TraceID,
    spanID: SpanID,
    name: String,
    status: StatusCode,
    end: UInt64,
    attributes: Attributes = Attributes([]),
    events: [SpanEventRecord] = []
  ) -> SpanRecord {
    SpanRecord(
      traceID: traceID,
      spanID: spanID,
      parentSpanID: nil,
      name: name,
      kind: .internal,
      status: status,
      startTimeUnixNano: 10,
      endTimeUnixNano: end,
      attributes: attributes,
      resource: Resource(attributes: Attributes([])),
      events: events
    )
  }

  func makeSecondaryRequest() -> Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest {
    let traceIDHex = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    let spanIDHex = "bbbbbbbbbbbbbbbb"

    let rootSpan = OTLPTestFixtures.makeSpan(
      traceIDHex: traceIDHex,
      spanIDHex: spanIDHex,
      parentSpanIDHex: nil,
      name: "root-secondary",
      kind: .server,
      status: .ok,
      startTimeUnixNano: OTLPTestFixtures.rootStart,
      endTimeUnixNano: OTLPTestFixtures.rootEnd,
      attributes: [("status.code", "ok")]
    )

    var resource = Opentelemetry_Proto_Resource_V1_Resource()
    resource.attributes = OTLPTestFixtures.resourceAttributes.map { key, value in
      OTLPTestFixtures.makeKeyValue(key: key, stringValue: value)
    }

    var scopeSpans = Opentelemetry_Proto_Trace_V1_ScopeSpans()
    scopeSpans.spans = [rootSpan]

    var resourceSpans = Opentelemetry_Proto_Trace_V1_ResourceSpans()
    resourceSpans.resource = resource
    resourceSpans.scopeSpans = [scopeSpans]

    var request = Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest()
    request.resourceSpans = [resourceSpans]
    return request
  }
}
