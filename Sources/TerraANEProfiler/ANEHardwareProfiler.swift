import Foundation
import TerraSystemProfiler
import CTerraANEBridge

public enum ANEHardwareProfiler {
  private static let state = ProfilerInstallState<ANEHardwareProfiler>()

  public static var isAvailable: Bool {
    terra_ane_is_available()
  }

  public static var isInstalled: Bool {
    state.isInstalled
  }

  @discardableResult
  public static func install() -> Bool {
    guard terra_ane_install_swizzling() else { return false }
    state.install()
    return true
  }

  public static func captureMetrics() -> ANEHardwareMetrics {
    ANEHardwareMetrics(from: terra_ane_get_metrics())
  }

  public static func reset() {
    terra_ane_reset_metrics()
  }
}
