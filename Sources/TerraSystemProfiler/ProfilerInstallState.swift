import Foundation

/// Thread-safe install state for profilers.
///
/// Uses a phantom `Marker` type parameter so each profiler gets its own distinct
/// instance type without duplicating the lock boilerplate.
///
/// ```swift
/// private static let state = ProfilerInstallState<ThermalMonitor>()
/// ```
package final class ProfilerInstallState<Marker>: @unchecked Sendable {
  private let lock = NSLock()
  private var _isInstalled = false

  package init() {}

  package func install() {
    lock.lock()
    _isInstalled = true
    lock.unlock()
  }

  package var isInstalled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return _isInstalled
  }
}
