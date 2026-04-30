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
