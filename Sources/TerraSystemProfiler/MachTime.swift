import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// High-resolution time measurement using Mach absolute time or system uptime.
///
/// ``MachTime`` provides cross-platform wall-clock-elapsed time measurement with
/// nanosecond precision on Darwin. It uses `mach_absolute_time()` internally on Apple
/// platforms, which is not affected by system clock changes.
///
/// ## Usage
/// ```swift
/// let start = MachTime.now()
/// // ... work ...
/// let elapsed = MachTime.elapsedMilliseconds(from: start, to: MachTime.now())
/// ```
public enum MachTime {

  #if canImport(Darwin)
  private static let timebase: mach_timebase_info_data_t = {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return info
  }()
  #endif

  /// A high-resolution timestamp from `mach_absolute_time()` or equivalent.
  ///
  /// Timestamps are opaque values; compute elapsed time using
  /// ``elapsedNanoseconds(from:to:)`` or ``elapsedMilliseconds(from:to:)``.
  public struct Timestamp: Sendable, Hashable {
    /// The raw timestamp value in Mach time units (platform-dependent).
    public let rawValue: UInt64

    /// Creates a timestamp from a raw Mach time value.
    public init(rawValue: UInt64) {
      self.rawValue = rawValue
    }
  }

  /// Returns the current timestamp.
  ///
  /// On Darwin, this uses `mach_absolute_time()` for monotonic, high-resolution timing.
  /// On other platforms, falls back to `Date()` converted to nanoseconds.
  ///
  /// - Returns: A ``Timestamp`` representing the current point in time.
  public static func now() -> Timestamp {
    #if canImport(Darwin)
    return Timestamp(rawValue: mach_absolute_time())
    #else
    return Timestamp(rawValue: UInt64(Date().timeIntervalSince1970 * 1_000_000_000))
    #endif
  }

  /// Computes elapsed time in nanoseconds between two timestamps.
  ///
  /// - Parameters:
  ///   - start: Starting timestamp.
  ///   - end: Ending timestamp.
  /// - Returns: Elapsed time in nanoseconds, or `0` if `end <= start`.
  public static func elapsedNanoseconds(from start: Timestamp, to end: Timestamp) -> UInt64 {
    #if canImport(Darwin)
    guard end.rawValue > start.rawValue else { return 0 }
    let elapsed = end.rawValue - start.rawValue
    return elapsed * UInt64(timebase.numer) / UInt64(timebase.denom)
    #else
    guard end.rawValue > start.rawValue else { return 0 }
    return end.rawValue - start.rawValue
    #endif
  }

  /// Computes elapsed time in milliseconds between two timestamps.
  ///
  /// - Parameters:
  ///   - start: Starting timestamp.
  ///   - end: Ending timestamp.
  /// - Returns: Elapsed time in milliseconds as a `Double`.
  public static func elapsedMilliseconds(from start: Timestamp, to end: Timestamp) -> Double {
    Double(elapsedNanoseconds(from: start, to: end)) / 1_000_000
  }
}
