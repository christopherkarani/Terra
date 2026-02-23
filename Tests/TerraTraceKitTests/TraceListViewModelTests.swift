import Foundation
import Testing
import OpenTelemetryApi
@testable import OpenTelemetrySdk
@testable import TerraTraceKit

private func makeSpan(
  name: String,
  traceId: TraceId,
  spanId: SpanId = SpanId.random()
) -> SpanData {
  SpanData(
    traceId: traceId,
    spanId: spanId,
    traceFlags: TraceFlags(),
    traceState: TraceState(),
    resource: Resource(),
    instrumentationScope: InstrumentationScopeInfo(),
    name: name,
    kind: .internal,
    startTime: Date(timeIntervalSince1970: 1_000),
    endTime: Date(timeIntervalSince1970: 1_001),
    hasRemoteParent: false,
    hasEnded: true
  )
}

private func makeTrace(fileName: String, name: String) throws -> Trace {
  let traceId = TraceId.random()
  let span = makeSpan(name: name, traceId: traceId)
  return try Trace(fileName: fileName, spans: [span])
}

@Test("TraceListViewModel clears selection when filtered out")
func traceListClearsSelectionWhenFiltered() throws {
  let first = try makeTrace(fileName: "1000", name: "alpha")
  let second = try makeTrace(fileName: "2000", name: "beta")

  let viewModel = TraceListViewModel(traces: [first, second])
  viewModel.selectTrace(id: first.id)

  viewModel.searchQuery = "beta"
  #expect(viewModel.selectedTrace == nil)
  #expect(viewModel.filteredTraces.count == 1)
}

@Test("TraceListViewModel clears selection when trace removed")
func traceListClearsSelectionWhenTraceRemoved() throws {
  let first = try makeTrace(fileName: "1000", name: "alpha")
  let second = try makeTrace(fileName: "2000", name: "beta")

  let viewModel = TraceListViewModel(traces: [first, second])
  viewModel.selectTrace(id: second.id)

  viewModel.updateTraces([first])
  #expect(viewModel.selectedTrace == nil)
  #expect(viewModel.filteredTraces.count == 1)
}
