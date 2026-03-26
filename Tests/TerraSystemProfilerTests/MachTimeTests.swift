import Foundation
import Testing
@testable import TerraSystemProfiler

@Suite("MachTime", .serialized)
struct MachTimeTests {

  @Test("now returns non-zero timestamp")
  func nowNonZero() {
    let ts = MachTime.now()
    #expect(ts.rawValue > 0)
  }

  @Test("elapsed positive for sequential calls")
  func elapsedPositive() {
    let start = MachTime.now()
    // Small busy loop to ensure measurable elapsed time
    var sum: UInt64 = 0
    for i in 0..<1000 { sum &+= UInt64(i) }
    _ = sum
    let end = MachTime.now()

    let nanos = MachTime.elapsedNanoseconds(from: start, to: end)
    #expect(nanos > 0)

    let ms = MachTime.elapsedMilliseconds(from: start, to: end)
    #expect(ms > 0)
  }

  @Test("elapsed returns zero when end is before start")
  func elapsedZeroWhenReversed() {
    let start = MachTime.Timestamp(rawValue: 1000)
    let end = MachTime.Timestamp(rawValue: 500)

    #expect(MachTime.elapsedNanoseconds(from: start, to: end) == 0)
    #expect(MachTime.elapsedMilliseconds(from: start, to: end) == 0)
  }

  @Test("Timestamp is Hashable")
  func timestampHashable() {
    let ts1 = MachTime.Timestamp(rawValue: 42)
    let ts2 = MachTime.Timestamp(rawValue: 42)
    #expect(ts1 == ts2)

    let set: Set<MachTime.Timestamp> = [ts1, ts2]
    #expect(set.count == 1)
  }
}
