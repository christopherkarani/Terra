import Foundation

#if canImport(Testing) && canImport(_TestingInternals)
import Testing
@testable import TraceMacAppUI
import TerraTraceKit

@Test
@MainActor
func spanListItemsAreOrderedByStartTime() async throws {
  let (viewModel, orderedSpans) = await makeSpanNavigationFixture()

  #expect(viewModel.spanListItems.map(\.spanID) == orderedSpans.map(\.spanID))
}

@Test
@MainActor
func selectNextSpanMovesSelectionForwardAndKeepsDetailInSync() async throws {
  let (viewModel, orderedSpans) = await makeSpanNavigationFixture()

  viewModel.selectedSpanID = orderedSpans[0].spanID
  viewModel.selectNextSpan()

  #expect(viewModel.selectedSpanID == orderedSpans[1].spanID)

  let selected = viewModel.spanListItems.first { $0.spanID == viewModel.selectedSpanID }
  #expect(selected?.spanID == orderedSpans[1].spanID)
}

@Test
@MainActor
func selectPreviousSpanMovesSelectionBackwardAndKeepsDetailInSync() async throws {
  let (viewModel, orderedSpans) = await makeSpanNavigationFixture()

  viewModel.selectedSpanID = orderedSpans[2].spanID
  viewModel.selectPreviousSpan()

  #expect(viewModel.selectedSpanID == orderedSpans[1].spanID)

  let selected = viewModel.spanListItems.first { $0.spanID == viewModel.selectedSpanID }
  #expect(selected?.spanID == orderedSpans[1].spanID)
}

@Test
@MainActor
func selectNextSpanAtEndKeepsSelectionInBounds() async throws {
  let (viewModel, orderedSpans) = await makeSpanNavigationFixture()

  viewModel.selectedSpanID = orderedSpans[2].spanID
  viewModel.selectNextSpan()

  #expect(viewModel.selectedSpanID == orderedSpans[2].spanID)
}

@Test
@MainActor
func selectPreviousSpanAtStartKeepsSelectionInBounds() async throws {
  let (viewModel, orderedSpans) = await makeSpanNavigationFixture()

  viewModel.selectedSpanID = orderedSpans[0].spanID
  viewModel.selectPreviousSpan()

  #expect(viewModel.selectedSpanID == orderedSpans[0].spanID)
}

@MainActor
private func makeSpanNavigationFixture() async -> (viewModel: TraceViewModel, orderedSpans: [SpanRecord]) {
  let store = TraceStore()
  let traceIDHex = "0123456789abcdef0123456789abcdef"

  let spanLate = makeSpan(
    traceIDHex: traceIDHex,
    spanIDHex: "1111111111111111",
    name: "span-late",
    startTimeUnixNano: 3_000,
    endTimeUnixNano: 4_000
  )
  let spanEarly = makeSpan(
    traceIDHex: traceIDHex,
    spanIDHex: "2222222222222222",
    name: "span-early",
    startTimeUnixNano: 1_000,
    endTimeUnixNano: 2_000
  )
  let spanMiddle = makeSpan(
    traceIDHex: traceIDHex,
    spanIDHex: "3333333333333333",
    name: "span-middle",
    startTimeUnixNano: 2_000,
    endTimeUnixNano: 3_000
  )

  _ = await store.ingest([spanLate, spanEarly, spanMiddle])

  let viewModel = TraceViewModel(traceStore: store)
  await viewModel.refresh()
  viewModel.selectedTraceID = spanLate.traceID

  return (viewModel, [spanEarly, spanMiddle, spanLate])
}
#endif
