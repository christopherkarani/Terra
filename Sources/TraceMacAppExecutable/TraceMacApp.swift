import AppKit
#if canImport(TraceMacAppUI)
import TraceMacAppUI
#endif

@main
enum TraceMacAppMain {
  private static var delegate: TraceMacAppDelegate?

  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let delegate = TraceMacAppDelegate()
    self.delegate = delegate
    app.delegate = delegate
    app.run()
  }
}

final class TraceMacAppDelegate: NSObject, NSApplicationDelegate {
  private var coordinator: AppCoordinator?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
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

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    guard !flag else { return true }
    coordinator?.showMainWindow()
    return true
  }
}
