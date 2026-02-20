import Foundation

#if canImport(Testing) && canImport(_TestingInternals)
import Testing
@testable import TraceMacAppUI
import TerraTraceKit

@Test
func traceTimelineModelNormalizesStartAndDuration() throws {
  let traceIDHex = "0123456789abcdef0123456789abcdef"
  let root = makeSpan(
    traceIDHex: traceIDHex,
    spanIDHex: "1111111111111111",
    name: "root",
    startTimeUnixNano: 100,
    endTimeUnixNano: 200
  )
  let child = makeSpan(
    traceIDHex: traceIDHex,
    spanIDHex: "2222222222222222",
    name: "child",
    startTimeUnixNano: 150,
    endTimeUnixNano: 180
  )

  let model = TraceTimelineModel(spans: [child, root])

  #expect(model.items.count == 2)

  let rootItem = try #require(model.items.first { $0.spanID == root.spanID })
  let childItem = try #require(model.items.first { $0.spanID == child.spanID })

  #expect(approxEqual(rootItem.normalizedStart, 0.0))
  #expect(approxEqual(rootItem.normalizedDuration, 1.0))

  #expect(approxEqual(childItem.normalizedStart, 0.5))
  #expect(approxEqual(childItem.normalizedDuration, 0.3))

  #expect(model.items.map(\.spanID) == [root.spanID, child.spanID])
}

private func approxEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.000_001) -> Bool {
  abs(lhs - rhs) <= tolerance
}
#endif
