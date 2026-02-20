import AppKit
import TraceMacAppUI

@main
final class TraceMacApp: NSObject, NSApplicationDelegate {
  private var coordinator: AppCoordinator?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSSetUncaughtExceptionHandler { exception in
      Task {
        await AppLog.shared.error(
          "uncaught_exception name=\(exception.name.rawValue) reason=\(exception.reason ?? "nil")"
        )
      }
    }
    Task { await AppLog.shared.info("app.did_finish_launching") }
    coordinator = AppCoordinator()
    coordinator?.start()
  }

  func applicationWillTerminate(_ notification: Notification) {
    Task { await AppLog.shared.info("app.will_terminate") }
  }
}
