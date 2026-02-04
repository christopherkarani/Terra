import Foundation

#if canImport(Testing) && canImport(_TestingInternals)
import Testing
@testable import TraceMacApp
import TerraTraceKit

@Test
@MainActor
func traceViewModelRefreshPullsSnapshotFromStore() async throws {
  let store = TraceStore()
  let spanA = makeSpan(
    traceIDHex: "0123456789abcdef0123456789abcdef",
    spanIDHex: "1111111111111111",
    name: "root-a",
    startTimeUnixNano: 1_000,
    endTimeUnixNano: 2_000
  )
  let spanB = makeSpan(
    traceIDHex: "abcdef0123456789abcdef0123456789",
    spanIDHex: "2222222222222222",
    name: "root-b",
    startTimeUnixNano: 3_000,
    endTimeUnixNano: 4_000
  )

  _ = await store.ingest([spanA, spanB])

  let viewModel = TraceViewModel(traceStore: store)
  await viewModel.refresh()

  #expect(viewModel.snapshot.allSpans.count == 2)
  #expect(viewModel.snapshot.traces[spanA.traceID]?.contains(spanA) == true)
  #expect(viewModel.snapshot.traces[spanB.traceID]?.contains(spanB) == true)
}

@Test
@MainActor
func traceViewModelRefreshAppliesFilter() async throws {
  let store = TraceStore()
  let spanA = makeSpan(
    traceIDHex: "0123456789abcdef0123456789abcdef",
    spanIDHex: "1111111111111111",
    name: "root-a",
    startTimeUnixNano: 1_000,
    endTimeUnixNano: 2_000
  )
  let spanB = makeSpan(
    traceIDHex: "abcdef0123456789abcdef0123456789",
    spanIDHex: "2222222222222222",
    name: "root-b",
    startTimeUnixNano: 3_000,
    endTimeUnixNano: 4_000
  )

  _ = await store.ingest([spanA, spanB])

  let filter = TraceFilter(traceID: spanA.traceID)
  let viewModel = TraceViewModel(traceStore: store, filter: filter)
  await viewModel.refresh()

  #expect(viewModel.snapshot.allSpans.count == 1)
  #expect(viewModel.snapshot.allSpans.first?.traceID == spanA.traceID)
}

@Test
@MainActor
func selectingTraceClearsSpanWhenNotInTrace() async throws {
  let store = TraceStore()
  let spanA = makeSpan(
    traceIDHex: "0123456789abcdef0123456789abcdef",
    spanIDHex: "1111111111111111",
    name: "root-a",
    startTimeUnixNano: 1_000,
    endTimeUnixNano: 2_000
  )
  let spanB = makeSpan(
    traceIDHex: "abcdef0123456789abcdef0123456789",
    spanIDHex: "2222222222222222",
    name: "root-b",
    startTimeUnixNano: 3_000,
    endTimeUnixNano: 4_000
  )

  _ = await store.ingest([spanA, spanB])

  let viewModel = TraceViewModel(traceStore: store)
  await viewModel.refresh()

  viewModel.selectedTraceID = spanA.traceID
  viewModel.selectedSpanID = spanA.spanID

  viewModel.selectedTraceID = spanB.traceID

  #expect(viewModel.selectedSpanID == nil)
}
#endif
