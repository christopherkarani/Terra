import Foundation
import CTerraANEBridge

public enum ANEProfilerSession {
  private static let lock = NSLock()
  private static var isActive = false

  public static func start() {
    lock.lock()
    defer { lock.unlock() }

    guard !isActive else { return }
    terra_ane_reset_metrics()
    isActive = true
  }

  public static func stop() -> ANEHardwareMetrics {
    lock.lock()
    defer { lock.unlock() }

    guard isActive else {
      return ANEHardwareMetrics(from: terra_ane_get_metrics())
    }

    isActive = false
    return ANEHardwareMetrics(from: terra_ane_get_metrics())
  }
}
