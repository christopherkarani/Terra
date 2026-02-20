import Foundation
import OpenTelemetryApi

#if canImport(Darwin)
import Darwin
#endif

public enum TerraSystemProfiler {
  public struct MemorySnapshot: Sendable {
    public let residentBytes: UInt64
    public let timestamp: Date
  }

  private static let lock = NSLock()
  private static var memoryProfilerEnabled = false

  public static func installMemoryProfiler() {
    lock.lock()
    memoryProfilerEnabled = true
    lock.unlock()
  }

  public static var isMemoryProfilerEnabled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return memoryProfilerEnabled
  }

  #if DEBUG
  public static func resetForTesting() {
    lock.lock()
    memoryProfilerEnabled = false
    lock.unlock()
  }
  #endif

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

  public static func memoryDeltaAttributes(
    start: MemorySnapshot?,
    end: MemorySnapshot?
  ) -> [String: AttributeValue] {
    guard let start, let end else { return [:] }
    let delta = Int64(end.residentBytes) - Int64(start.residentBytes)
    return [
      "terra.process.memory_resident_delta_mb": .double(Double(delta) / 1_048_576),
      "terra.process.memory_peak_mb": .double(Double(max(start.residentBytes, end.residentBytes)) / 1_048_576),
    ]
  }
}
