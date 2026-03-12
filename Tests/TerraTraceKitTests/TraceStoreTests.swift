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
  func testIngestWithZeroMaxSpansKeepsNoSpans() async throws {
    let decoder = OTLPRequestDecoder(maxBodyBytes: 1_000_000, maxDecompressedBytes: 1_000_000)
    let body = try OTLPTestFixtures.serializedRequest()
    let spans = try decoder.decode(body: body, headers: ["Content-Encoding": "identity"])

    let store = TraceStore(maxSpans: 0)
    let accepted = await store.ingest(spans)
    let snapshot = await store.snapshot(filter: nil)

    XCTAssertTrue(accepted.isEmpty)
    XCTAssertTrue(snapshot.allSpans.isEmpty)
    XCTAssertTrue(snapshot.traces.isEmpty)
  }

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
}

private extension TraceStoreTests {
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
