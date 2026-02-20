import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum ThreadProfiler {
  public struct ThreadSnapshot: Sendable {
    public let threadCountEstimate: Int
    public let sampleTime: Date
  }

  public static func capture() -> ThreadSnapshot {
    #if canImport(Darwin)
    var threads: thread_act_array_t?
    var threadCount: mach_msg_type_number_t = 0
    let result = task_threads(mach_task_self_, &threads, &threadCount)
    if result == KERN_SUCCESS {
      if let threads {
        let deallocateSize = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)), deallocateSize)
      }
      return ThreadSnapshot(
        threadCountEstimate: Int(threadCount),
        sampleTime: Date()
      )
    }
    #endif

    // Fallback for non-Darwin targets and task query failures.
    return ThreadSnapshot(
      threadCountEstimate: ProcessInfo.processInfo.activeProcessorCount,
      sampleTime: Date()
    )
  }
}
