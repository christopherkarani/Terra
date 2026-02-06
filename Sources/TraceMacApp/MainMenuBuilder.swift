import AppKit

@objc protocol MainMenuCoordinating: AnyObject {
  func checkForUpdates(_ sender: Any?)
  func showQuickstart(_ sender: Any?)

  func activateLicense(_ sender: Any?)
  func showLicenseStatus(_ sender: Any?)
  func deactivateLicense(_ sender: Any?)

  func chooseTracesFolder(_ sender: Any?)
  func openTracesFolder(_ sender: Any?)
  func loadSampleTraces(_ sender: Any?)
  func exportDiagnostics(_ sender: Any?)
  func reloadTraces(_ sender: Any?)

  func toggleWatchTracesFolder(_ sender: Any?)

  func openPrivacyPolicy(_ sender: Any?)
  func openEULA(_ sender: Any?)
  func toggleCrashReporting(_ sender: Any?)
  func toggleAutomaticUpdateChecks(_ sender: Any?)
  func revealCrashReports(_ sender: Any?)
}

enum MainMenuBuilder {
  static func install(coordinator: any MainMenuCoordinating) {
    let mainMenu = NSMenu(title: "MainMenu")

    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    appMenuItem.submenu = makeAppMenu(coordinator: coordinator)

    let fileMenuItem = NSMenuItem()
    fileMenuItem.title = "File"
    mainMenu.addItem(fileMenuItem)
    fileMenuItem.submenu = makeFileMenu(coordinator: coordinator)

    let viewMenuItem = NSMenuItem()
    viewMenuItem.title = "View"
    mainMenu.addItem(viewMenuItem)
    viewMenuItem.submenu = makeViewMenu(coordinator: coordinator)

    let helpMenuItem = NSMenuItem()
    helpMenuItem.title = "Help"
    mainMenu.addItem(helpMenuItem)
    helpMenuItem.submenu = makeHelpMenu(coordinator: coordinator)

    NSApp.mainMenu = mainMenu
  }

  private static func makeAppMenu(coordinator: any MainMenuCoordinating) -> NSMenu {
    let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? ProcessInfo.processInfo.processName

    let menu = NSMenu(title: appName)

    menu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    menu.addItem(.separator())

    let updates = NSMenuItem(
      title: "Check for Updates…",
      action: #selector(MainMenuCoordinating.checkForUpdates(_:)),
      keyEquivalent: ""
    )
    updates.target = coordinator
    menu.addItem(updates)

    let quickstart = NSMenuItem(
      title: "Instrument Your App (60s)…",
      action: #selector(MainMenuCoordinating.showQuickstart(_:)),
      keyEquivalent: ""
    )
    quickstart.target = coordinator
    menu.addItem(quickstart)

    menu.addItem(.separator())

    let activateLicense = NSMenuItem(
      title: "Activate License…",
      action: #selector(MainMenuCoordinating.activateLicense(_:)),
      keyEquivalent: "a"
    )
    activateLicense.keyEquivalentModifierMask = [.command, .shift]
    activateLicense.target = coordinator
    menu.addItem(activateLicense)

    let licenseStatus = NSMenuItem(
      title: "License Status…",
      action: #selector(MainMenuCoordinating.showLicenseStatus(_:)),
      keyEquivalent: ""
    )
    licenseStatus.target = coordinator
    menu.addItem(licenseStatus)

    let deactivateLicense = NSMenuItem(
      title: "Deactivate License",
      action: #selector(MainMenuCoordinating.deactivateLicense(_:)),
      keyEquivalent: ""
    )
    deactivateLicense.target = coordinator
    menu.addItem(deactivateLicense)

    menu.addItem(.separator())

    let quit = NSMenuItem(title: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    menu.addItem(quit)

    return menu
  }

  private static func makeFileMenu(coordinator: any MainMenuCoordinating) -> NSMenu {
    let menu = NSMenu(title: "File")

    let chooseFolder = NSMenuItem(
      title: "Choose Traces Folder…",
      action: #selector(MainMenuCoordinating.chooseTracesFolder(_:)),
      keyEquivalent: "o"
    )
    chooseFolder.target = coordinator
    menu.addItem(chooseFolder)

    let openFolder = NSMenuItem(
      title: "Open Traces Folder in Finder",
      action: #selector(MainMenuCoordinating.openTracesFolder(_:)),
      keyEquivalent: "O"
    )
    openFolder.keyEquivalentModifierMask = [.command, .shift]
    openFolder.target = coordinator
    menu.addItem(openFolder)

    menu.addItem(.separator())

    let sample = NSMenuItem(
      title: "Load Sample Traces",
      action: #selector(MainMenuCoordinating.loadSampleTraces(_:)),
      keyEquivalent: "l"
    )
    sample.keyEquivalentModifierMask = [.command, .shift]
    sample.target = coordinator
    menu.addItem(sample)

    menu.addItem(.separator())

    let exportDiagnostics = NSMenuItem(
      title: "Export Diagnostics…",
      action: #selector(MainMenuCoordinating.exportDiagnostics(_:)),
      keyEquivalent: "d"
    )
    exportDiagnostics.keyEquivalentModifierMask = [.command, .shift]
    exportDiagnostics.target = coordinator
    menu.addItem(exportDiagnostics)

    menu.addItem(.separator())

    let reload = NSMenuItem(
      title: "Reload Traces",
      action: #selector(MainMenuCoordinating.reloadTraces(_:)),
      keyEquivalent: "r"
    )
    reload.target = coordinator
    menu.addItem(reload)

    return menu
  }

  private static func makeViewMenu(coordinator: any MainMenuCoordinating) -> NSMenu {
    let menu = NSMenu(title: "View")

    let watch = NSMenuItem(
      title: "Watch Traces Folder",
      action: #selector(MainMenuCoordinating.toggleWatchTracesFolder(_:)),
      keyEquivalent: "w"
    )
    watch.keyEquivalentModifierMask = [.command, .shift]
    watch.target = coordinator
    menu.addItem(watch)

    return menu
  }

  private static func makeHelpMenu(coordinator: any MainMenuCoordinating) -> NSMenu {
    let menu = NSMenu(title: "Help")

    let privacy = NSMenuItem(
      title: "Privacy Policy…",
      action: #selector(MainMenuCoordinating.openPrivacyPolicy(_:)),
      keyEquivalent: ""
    )
    privacy.target = coordinator
    menu.addItem(privacy)

    let eula = NSMenuItem(
      title: "EULA…",
      action: #selector(MainMenuCoordinating.openEULA(_:)),
      keyEquivalent: ""
    )
    eula.target = coordinator
    menu.addItem(eula)

    menu.addItem(.separator())

    let crashReporting = NSMenuItem(
      title: "Enable Crash Reporting",
      action: #selector(MainMenuCoordinating.toggleCrashReporting(_:)),
      keyEquivalent: ""
    )
    crashReporting.target = coordinator
    menu.addItem(crashReporting)

    let automaticUpdates = NSMenuItem(
      title: "Enable Automatic Update Checks",
      action: #selector(MainMenuCoordinating.toggleAutomaticUpdateChecks(_:)),
      keyEquivalent: ""
    )
    automaticUpdates.target = coordinator
    menu.addItem(automaticUpdates)

    menu.addItem(.separator())

    let crashReports = NSMenuItem(
      title: "Reveal Crash Reports in Finder",
      action: #selector(MainMenuCoordinating.revealCrashReports(_:)),
      keyEquivalent: ""
    )
    crashReports.target = coordinator
    menu.addItem(crashReports)

    return menu
  }
}
