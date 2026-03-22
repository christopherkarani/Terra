import Foundation
import OpenTelemetryApi

#if canImport(Darwin)
import Darwin
#endif

/// System-level profiler for process memory and resource metrics.
///
/// TerraSystemProfiler provides lightweight system-level profiling hooks for capturing
/// process memory usage and thermal state. These profilers are designed to have minimal
/// overhead and can be enabled/disabled at runtime.
///
/// ## Memory Profiling
///
/// Use ``captureMemorySnapshot()`` to capture process memory state at any point:
/// ```swift
/// let start = TerraSystemProfiler.captureMemorySnapshot()
/// // ... run inference ...
/// let end = TerraSystemProfiler.captureMemorySnapshot()
/// let delta = TerraSystemProfiler.memoryDeltaAttributes(start: start, end: end)
/// ```
///
/// ## Installation
///
/// Call ``install()`` once during app initialization to enable memory profiling:
/// ```swift
/// TerraSystemProfiler.install()
/// ```
public enum TerraSystemProfiler {
  /// Snapshot of process memory usage at a point in time.
  ///
  /// Contains the resident byte count and timestamp. Use with
  /// ``memoryDeltaAttributes(start:end:)`` to compute memory deltas between
  /// two snapshots.
  public struct MemorySnapshot: Sendable, TelemetryAttributeConvertible {
    /// Resident memory size in bytes.
    public let residentBytes: UInt64

    /// Time when the snapshot was captured.
    public let timestamp: Date

    /// Converts the memory snapshot into OpenTelemetry span attributes.
    ///
    /// Produces:
    /// - `process.memory.resident_bytes` (int): Resident memory in bytes.
    /// - `process.memory.resident_mb` (double): Resident memory in megabytes.
    public var telemetryAttributes: [String: AttributeValue] {
      [
        "process.memory.resident_bytes": .int(Int(residentBytes)),
        "process.memory.resident_mb": .double(Double(residentBytes) / 1_048_576),
      ]
    }
  }

  private static let state = ProfilerInstallState<TerraSystemProfiler>()

  /// Installs the system profiler hooks.
  ///
  /// Call this once during app initialization before capturing any memory snapshots.
  /// Installation is idempotent — calling multiple times has no additional effect.
  public static func install() {
    state.install()
  }

  /// Returns `true` if the system profiler has been installed.
  public static var isInstalled: Bool {
    state.isInstalled
  }

  /// Captures the current process memory snapshot.
  ///
  /// - Returns: ``MemorySnapshot`` containing current resident memory size and timestamp,
  ///   or `nil` if capture failed.
  public static func captureMemorySnapshot() -> MemorySnapshot? {
    #if canImport(Darwin)
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size) / 4
    let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    return MemorySnapshot(residentBytes: UInt64(info.resident_size), timestamp: Date())
    #else
    return nil
    #endif
  }

  /// Computes memory delta attributes between two snapshots.
  ///
  /// - Parameters:
  ///   - start: Starting memory snapshot, or `nil` to use zero as baseline.
  ///   - end: Ending memory snapshot, or `nil` to use current memory as endpoint.
  ///
  /// - Returns: Dictionary containing:
  ///   - `process.memory.resident_delta_mb`: Change in resident memory between snapshots.
  ///   - `process.memory.peak_mb`: Highest memory seen across both snapshots.
  ///   Returns an empty dictionary if either snapshot is `nil`.
  public static func memoryDeltaAttributes(
    start: MemorySnapshot?,
    end: MemorySnapshot?
  ) -> [String: AttributeValue] {
    guard let start, let end else { return [:] }
    let delta = Int64(end.residentBytes) - Int64(start.residentBytes)
    return [
      "process.memory.resident_delta_mb": .double(Double(delta) / 1_048_576),
      "process.memory.peak_mb": .double(Double(max(start.residentBytes, end.residentBytes)) / 1_048_576),
    ]
  }
}
