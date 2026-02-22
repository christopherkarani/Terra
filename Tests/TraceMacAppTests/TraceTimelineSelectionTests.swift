import CoreGraphics
import Foundation

#if canImport(Testing) && canImport(_TestingInternals)
import Testing
@testable import TraceMacApp
import TerraTraceKit

@Test
@MainActor
func traceTimelineHitTesterReturnsSpanForBarPoint() throws {
  let traceIDHex = "0123456789abcdef0123456789abcdef"
  let spanA = makeSpan(
    traceIDHex: traceIDHex,
    spanIDHex: "1111111111111111",
    name: "root-a",
    startTimeUnixNano: 0,
    endTimeUnixNano: 100
  )
  let spanB = makeSpan(
    traceIDHex: traceIDHex,
    spanIDHex: "2222222222222222",
    name: "root-b",
    startTimeUnixNano: 100,
    endTimeUnixNano: 200
  )

  let model = TraceTimelineModel(spans: [spanA, spanB])
  let bounds = CGRect(x: 0, y: 0, width: 200, height: 120)

  let horizontalPadding = TraceUIStyle.Spacing.large
  let verticalPadding = TraceUIStyle.Spacing.large
  let rowHeight = TraceUIStyle.Sizing.timelineRowHeight
  let rowStride = rowHeight + TraceUIStyle.Sizing.timelineRowSpacing
  let contentWidth = bounds.width - (horizontalPadding * 2)

  let x = horizontalPadding + (0.75 * contentWidth)
  let y = verticalPadding + rowStride + (rowHeight * 0.5)

  let hit = TraceTimelineHitTester.spanID(
    at: CGPoint(x: x, y: y),
    in: bounds,
    items: model.items
  )

  #expect(hit == spanB.spanID)
}

@Test
func traceTimelineModelMarksSelectedSpan() throws {
  let traceIDHex = "0123456789abcdef0123456789abcdef"
  let spanA = makeSpan(
    traceIDHex: traceIDHex,
    spanIDHex: "1111111111111111",
    name: "root-a",
    startTimeUnixNano: 0,
    endTimeUnixNano: 100
  )
  let spanB = makeSpan(
    traceIDHex: traceIDHex,
    spanIDHex: "2222222222222222",
    name: "root-b",
    startTimeUnixNano: 100,
    endTimeUnixNano: 200
  )

  let model = TraceTimelineModel(spans: [spanA, spanB], selectedSpanID: spanB.spanID)

  let selectedItem = try #require(model.items.first { $0.spanID == spanB.spanID })
  let otherItem = try #require(model.items.first { $0.spanID == spanA.spanID })

  #expect(selectedItem.isSelected)
  #expect(otherItem.isSelected == false)
}

@Test
@MainActor
func traceViewModelSelectedSpanTracksSelection() async throws {
  let store = TraceStore()
  let traceIDHex = "0123456789abcdef0123456789abcdef"
  let spanA = makeSpan(
    traceIDHex: traceIDHex,
    spanIDHex: "1111111111111111",
    name: "root-a",
    startTimeUnixNano: 0,
    endTimeUnixNano: 100
  )
  let spanB = makeSpan(
    traceIDHex: traceIDHex,
    spanIDHex: "2222222222222222",
    name: "root-b",
    startTimeUnixNano: 100,
    endTimeUnixNano: 200
  )

  _ = await store.ingest([spanA, spanB])

  let viewModel = TraceViewModel(traceStore: store)
  await viewModel.refresh()

  viewModel.selectedTraceID = spanA.traceID
  viewModel.selectedSpanID = spanA.spanID

  #expect(viewModel.selectedSpan?.spanID == spanA.spanID)

  viewModel.selectedSpanID = spanB.spanID

  #expect(viewModel.selectedSpan?.spanID == spanB.spanID)
}
#endif
