import Foundation

/// A lightweight snapshot of thread utilization at a point in time.
///
/// ``ThreadSnapshot`` provides an estimate of active thread count. This is useful
/// for correlating inference performance with concurrency levels.
public enum ThreadProfiler {
  /// Snapshot of thread utilization at a point in time.
  public struct ThreadSnapshot: Sendable {
    /// Estimated number of active threads.
    ///
    /// On Darwin, this is currently reported as `ProcessInfo.activeProcessorCount`.
    /// A future implementation may use mach thread introspection for precise counts.
    public let threadCountEstimate: Int

    /// Wall-clock time when the snapshot was captured.
    public let sampleTime: Date
  }

  /// Captures a thread utilization snapshot.
  ///
  /// - Returns: A ``ThreadSnapshot`` with the current estimated thread count and timestamp.
  public static func capture() -> ThreadSnapshot {
    // Placeholder estimate; can be replaced with mach thread introspection later.
    ThreadSnapshot(
      threadCountEstimate: ProcessInfo.processInfo.activeProcessorCount,
      sampleTime: Date()
    )
  }
}
