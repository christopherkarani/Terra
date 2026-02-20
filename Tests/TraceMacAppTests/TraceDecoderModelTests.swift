import Foundation
import Testing
import OpenTelemetryApi
@testable import OpenTelemetrySdk
@testable import TerraTraceKit

private func makeSpan(
  name: String,
  traceId: TraceId = TraceId(),
  spanId: SpanId = SpanId.random(),
  parentSpanId: SpanId? = nil,
  start: Date,
  end: Date,
  status: Status = .unset
) -> SpanData {
  var span = SpanData(
    traceId: traceId,
    spanId: spanId,
    traceFlags: TraceFlags(),
    traceState: TraceState(),
    resource: Resource(),
    instrumentationScope: InstrumentationScopeInfo(),
    name: name,
    kind: .internal,
    startTime: start,
    endTime: end,
    hasRemoteParent: false,
    hasEnded: true
  )
  if let parentSpanId {
    span = span.settingParentSpanId(parentSpanId)
  }
  span = span.settingStatus(status)
  return span
}

@Test("TraceDecoder wraps comma-separated arrays before decoding")
func traceDecoderWrapsCommaSeparatedArrays() throws {
  let span = makeSpan(
    name: "root",
    start: Date(timeIntervalSince1970: 1000),
    end: Date(timeIntervalSince1970: 1001)
  )
  let arrayData = try JSONEncoder().encode([span])
  var fileData = Data(arrayData)
  fileData.append(Data(",".utf8))

  let decoded = try TraceDecoder().decodeSpans(from: fileData)
  #expect(decoded.count == 1)
  #expect(decoded.first?.name == "root")
}

@Test("TraceDecoder returns empty array for empty or whitespace-only data")
func traceDecoderHandlesEmptyData() throws {
  let decoder = TraceDecoder()
  let empty = try decoder.decodeSpans(from: Data())
  #expect(empty.isEmpty)

  let whitespace = try decoder.decodeSpans(from: Data("\n  \t".utf8))
  #expect(whitespace.isEmpty)
}

@Test("TraceDecoder throws a decoding error for invalid JSON")
func traceDecoderThrowsOnInvalidJSON() {
  #expect(throws: TraceDecodingError.self) {
    _ = try TraceDecoder().decodeSpans(from: Data("not json,".utf8))
  }
}

@Test("Trace model derives stable identifiers and boundaries")
func traceModelComputesBoundaries() throws {
  let traceId = TraceId()
  let rootSpanId = SpanId.random()
  let childSpanId = SpanId.random()

  let root = makeSpan(
    name: "root",
    traceId: traceId,
    spanId: rootSpanId,
    start: Date(timeIntervalSince1970: 10),
    end: Date(timeIntervalSince1970: 20)
  )
  let child = makeSpan(
    name: "child",
    traceId: traceId,
    spanId: childSpanId,
    parentSpanId: rootSpanId,
    start: Date(timeIntervalSince1970: 12),
    end: Date(timeIntervalSince1970: 18),
    status: .error(description: "boom")
  )

  let trace = try Trace(fileName: "123456", spans: [child, root])
  #expect(trace.id == "123456")
  #expect(trace.traceId == traceId)
  #expect(trace.startTime == root.startTime)
  #expect(trace.endTime == root.endTime)
  #expect(trace.duration == 10)
  #expect(trace.rootSpans.count == 1)
  #expect(trace.rootSpans.first?.name == "root")
  #expect(trace.orderedSpans.map(\.name) == ["root", "child"])
  #expect(trace.hasError == true)
}
