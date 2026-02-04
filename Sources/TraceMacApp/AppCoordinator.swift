import AppKit
import TerraTraceKit

@MainActor
final class AppCoordinator {
  private let traceStore: TraceStore
  private let server: OTLPHTTPServer
  private var window: NSWindow?
  private var toolbarProvider: TraceToolbarProvider?

  init(host: String = "127.0.0.1", port: UInt16 = 4318) {
    self.traceStore = TraceStore()
    self.server = OTLPHTTPServer(host: host, port: port, traceStore: traceStore)
  }

  func start() {
    configureMainMenu()
    do {
      try server.start()
    } catch {
      presentStartFailure(error)
      return
    }
    showWindow()
  }

  func stop() {
    server.stop()
  }

  private func showWindow() {
    let viewModel = TraceViewModel(traceStore: traceStore)
    let rootViewController = TraceSplitViewController(viewModel: viewModel)

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "TraceMacApp"
    window.contentViewController = rootViewController
    window.center()
    window.makeKeyAndOrderFront(nil)

    let toolbarProvider = TraceToolbarProvider()
    window.toolbar = toolbarProvider.toolbar
    self.toolbarProvider = toolbarProvider

    self.window = window
    NSApp.activate(ignoringOtherApps: true)
  }

  private func configureMainMenu() {
    let mainMenu = NSMenu()
    let appItem = NSMenuItem()
    mainMenu.addItem(appItem)

    let appMenu = NSMenu()
    let quitTitle = "Quit \(ProcessInfo.processInfo.processName)"
    let quitItem = NSMenuItem(
      title: quitTitle,
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    appMenu.addItem(quitItem)
    appItem.submenu = appMenu

    NSApp.mainMenu = mainMenu
  }

  private func presentStartFailure(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = "Failed to start trace server"
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .critical
    alert.addButton(withTitle: "Quit")
    alert.runModal()
    NSApp.terminate(nil)
  }
}
