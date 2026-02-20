import Foundation

public enum ThreadProfiler {
  public struct ThreadSnapshot: Sendable {
    public let threadCountEstimate: Int
    public let sampleTime: Date
  }

  public static func capture() -> ThreadSnapshot {
    // Placeholder estimate; can be replaced with mach thread introspection later.
    ThreadSnapshot(
      threadCountEstimate: ProcessInfo.processInfo.activeProcessorCount,
      sampleTime: Date()
    )
  }
}
