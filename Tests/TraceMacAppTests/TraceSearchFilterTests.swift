import Foundation

#if canImport(Testing) && canImport(_TestingInternals)
import Testing
@testable import TraceMacApp
import TerraTraceKit

@Test
@MainActor
func updateSearchQueryParsesTracePrefix() {
  let store = TraceStore()
  let viewModel = TraceViewModel(traceStore: store)
  let traceHex = "0123456789abcdef0123456789abcdef"

  viewModel.updateSearchQuery("trace:\(traceHex)")

  #expect(viewModel.searchFilter?.traceID == makeTraceID(traceHex))
  #expect(viewModel.searchFilter?.namePrefix == nil)
}

@Test
@MainActor
func updateSearchQueryParsesNamePrefix() {
  let store = TraceStore()
  let viewModel = TraceViewModel(traceStore: store)

  viewModel.updateSearchQuery("name:root")

  #expect(viewModel.searchFilter?.traceID == nil)
  #expect(viewModel.searchFilter?.namePrefix == "root")
}

@Test
@MainActor
func updateSearchQueryDefaultsToNamePrefix() {
  let store = TraceStore()
  let viewModel = TraceViewModel(traceStore: store)

  viewModel.updateSearchQuery("root")

  #expect(viewModel.searchFilter?.traceID == nil)
  #expect(viewModel.searchFilter?.namePrefix == "root")
}

@Test
@MainActor
func updateSearchQueryTreats32HexAsTraceID() {
  let store = TraceStore()
  let viewModel = TraceViewModel(traceStore: store)
  let traceHex = "abcdef0123456789abcdef0123456789"

  viewModel.updateSearchQuery(traceHex)

  #expect(viewModel.searchFilter?.traceID == makeTraceID(traceHex))
  #expect(viewModel.searchFilter?.namePrefix == nil)
}

@Test
@MainActor
func searchFilterIsAppliedWhenRefreshingSnapshot() async throws {
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
    name: "other",
    startTimeUnixNano: 3_000,
    endTimeUnixNano: 4_000
  )

  _ = await store.ingest([spanA, spanB])

  let viewModel = TraceViewModel(traceStore: store)
  viewModel.updateSearchQuery("name:root")
  await viewModel.refresh()

  #expect(viewModel.snapshot.allSpans.count == 1)
  #expect(viewModel.snapshot.allSpans.contains { $0.spanID == spanA.spanID })
  #expect(viewModel.snapshot.allSpans.contains { $0.spanID == spanB.spanID } == false)
}
#endif
