import Foundation
import Testing
import OpenTelemetryApi
@testable import OpenTelemetrySdk
@testable import TerraTraceKit

private func makeSpan(
  name: String,
  traceId: TraceId,
  spanId: SpanId = SpanId(),
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

@Test("TraceListViewModel sorts by newest and filters by id or name")
func traceListViewModelSortsAndFilters() throws {
  let traceIdA = TraceId()
  let traceIdB = TraceId()

  let spanA = makeSpan(
    name: "LoadHome",
    traceId: traceIdA,
    start: Date(timeIntervalSince1970: 10),
    end: Date(timeIntervalSince1970: 20)
  )
  let spanB = makeSpan(
    name: "Checkout",
    traceId: traceIdB,
    start: Date(timeIntervalSince1970: 30),
    end: Date(timeIntervalSince1970: 40)
  )

  let traceA = try Trace(fileName: "1000", spans: [spanA])
  let traceB = try Trace(fileName: "2000", spans: [spanB])

  let viewModel = TraceListViewModel(traces: [traceA, traceB])
  #expect(viewModel.filteredTraces.map(\.id) == ["2000", "1000"])

  viewModel.searchQuery = "1000"
  #expect(viewModel.filteredTraces.map(\.id) == ["1000"])

  viewModel.searchQuery = "Checkout"
  #expect(viewModel.filteredTraces.map(\.id) == ["2000"])
}

@Test("TraceListViewModel maintains selection state")
func traceListViewModelSelection() throws {
  let traceId = TraceId()
  let span = makeSpan(
    name: "Root",
    traceId: traceId,
    start: Date(timeIntervalSince1970: 10),
    end: Date(timeIntervalSince1970: 20)
  )
  let trace = try Trace(fileName: "1000", spans: [span])
  let viewModel = TraceListViewModel(traces: [trace])

  viewModel.selectTrace(id: "1000")
  #expect(viewModel.selectedTrace?.id == "1000")
}

@Test("TimelineViewModel places overlapping spans into separate lanes")
func timelineViewModelLanes() throws {
  let traceId = TraceId()
  let span1 = makeSpan(
    name: "A",
    traceId: traceId,
    start: Date(timeIntervalSince1970: 0),
    end: Date(timeIntervalSince1970: 10)
  )
  let span2 = makeSpan(
    name: "B",
    traceId: traceId,
    start: Date(timeIntervalSince1970: 5),
    end: Date(timeIntervalSince1970: 12)
  )
  let span3 = makeSpan(
    name: "C",
    traceId: traceId,
    start: Date(timeIntervalSince1970: 12),
    end: Date(timeIntervalSince1970: 20)
  )

  let trace = try Trace(fileName: "1000", spans: [span1, span2, span3])
  let timeline = TimelineViewModel(trace: trace)

  #expect(timeline.lanes.count == 2)
  #expect(timeline.lanes.flatMap(\.items).map(\.span.name).sorted() == ["A", "B", "C"])
}

@Test("TimelineViewModel marks error and long spans as important")
func timelineViewModelHighlightsImportantSpans() throws {
  let traceId = TraceId()
  let normal = makeSpan(
    name: "Normal",
    traceId: traceId,
    start: Date(timeIntervalSince1970: 0),
    end: Date(timeIntervalSince1970: 1)
  )
  let errorSpan = makeSpan(
    name: "Error",
    traceId: traceId,
    start: Date(timeIntervalSince1970: 2),
    end: Date(timeIntervalSince1970: 3),
    status: .error(description: "boom")
  )
  let longSpan = makeSpan(
    name: "Long",
    traceId: traceId,
    start: Date(timeIntervalSince1970: 4),
    end: Date(timeIntervalSince1970: 10)
  )

  let trace = try Trace(fileName: "1000", spans: [normal, errorSpan, longSpan])
  let timeline = TimelineViewModel(trace: trace)

  let errorItem = timeline.lanes.flatMap(\.items).first { $0.span.name == "Error" }
  let longItem = timeline.lanes.flatMap(\.items).first { $0.span.name == "Long" }

  #expect(errorItem?.isError == true)
  #expect(longItem?.isCritical == true)
}

@Test("SpanDetailViewModel exposes attributes, events, and links")
func spanDetailViewModelSelection() throws {
  let traceId = TraceId()
  var span = makeSpan(
    name: "Root",
    traceId: traceId,
    start: Date(timeIntervalSince1970: 1),
    end: Date(timeIntervalSince1970: 2)
  )
  span = span.settingAttributes(["http.method": .string("GET")])
  span = span.settingEvents([SpanData.Event(name: "event", timestamp: Date())])
  let linkContext = SpanContext.create(traceId: traceId, spanId: SpanId(), traceFlags: TraceFlags(), traceState: TraceState())
  span = span.settingLinks([SpanData.Link(context: linkContext)])

  let detail = SpanDetailViewModel()
  detail.select(span: span)

  #expect(detail.attributeItems.count == 1)
  #expect(detail.eventItems.count == 1)
  #expect(detail.linkItems.count == 1)

  detail.clearSelection()
  #expect(detail.attributeItems.isEmpty)
  #expect(detail.eventItems.isEmpty)
  #expect(detail.linkItems.isEmpty)
}
