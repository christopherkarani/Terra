import Foundation

#if canImport(Darwin)
import Darwin
#endif

public enum MachTime {

  public struct Timestamp: Sendable, Hashable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
      self.rawValue = rawValue
    }
  }

  public static func now() -> Timestamp {
    #if canImport(Darwin)
    return Timestamp(rawValue: mach_absolute_time())
    #else
    return Timestamp(rawValue: UInt64(Date().timeIntervalSince1970 * 1_000_000_000))
    #endif
  }

  public static func elapsedNanoseconds(from start: Timestamp, to end: Timestamp) -> UInt64 {
    #if canImport(Darwin)
    guard end.rawValue > start.rawValue else { return 0 }
    let elapsed = end.rawValue - start.rawValue
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    return elapsed * UInt64(timebase.numer) / UInt64(timebase.denom)
    #else
    guard end.rawValue > start.rawValue else { return 0 }
    return end.rawValue - start.rawValue
    #endif
  }

  public static func elapsedMilliseconds(from start: Timestamp, to end: Timestamp) -> Double {
    Double(elapsedNanoseconds(from: start, to: end)) / 1_000_000
  }
}
