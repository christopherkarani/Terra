import AppKit
import Testing
@testable import TraceMacAppUI

@MainActor
@Suite("Main Menu Builder", .serialized)
struct MainMenuBuilderTests {
  init() {
    _ = NSApplication.shared
  }

  @Test("MainMenuBuilder installs expected menus and key equivalents")
  func mainMenuBuilderInstallsExpectedMenu() throws {
    final class TestCoordinator: NSObject, MainMenuCoordinating {
      func checkForUpdates(_ sender: Any?) {}
      func showQuickstart(_ sender: Any?) {}

      func activateLicense(_ sender: Any?) {}
      func showLicenseStatus(_ sender: Any?) {}
      func deactivateLicense(_ sender: Any?) {}

      func chooseTracesFolder(_ sender: Any?) {}
      func openTracesFolder(_ sender: Any?) {}
      func loadSampleTraces(_ sender: Any?) {}
      func exportDiagnostics(_ sender: Any?) {}
      func reloadTraces(_ sender: Any?) {}

      func toggleWatchTracesFolder(_ sender: Any?) {}

      func openPrivacyPolicy(_ sender: Any?) {}
      func openEULA(_ sender: Any?) {}
      func toggleCrashReporting(_ sender: Any?) {}
      func toggleAutomaticUpdateChecks(_ sender: Any?) {}
      func revealCrashReports(_ sender: Any?) {}
    }

    let coordinator = TestCoordinator()
    MainMenuBuilder.install(coordinator: coordinator)

    let mainMenu = try #require(NSApp.mainMenu)
    #expect(mainMenu.items.count == 4)

    let appMenu = try #require(mainMenu.items.first?.submenu)
    let fileMenu = try #require(mainMenu.item(withTitle: "File")?.submenu)
    let viewMenu = try #require(mainMenu.item(withTitle: "View")?.submenu)
    let helpMenu = try #require(mainMenu.item(withTitle: "Help")?.submenu)

    func item(_ title: String, in menu: NSMenu) -> NSMenuItem? {
      menu.items.first(where: { $0.title == title })
    }

    let activate = try #require(item("Activate License…", in: appMenu))
    #expect(activate.action == #selector(MainMenuCoordinating.activateLicense(_:)))
    #expect(activate.keyEquivalent == "a")
    #expect(activate.keyEquivalentModifierMask.contains(.command))
    #expect(activate.keyEquivalentModifierMask.contains(.shift))
    #expect(activate.target === coordinator)

    let chooseFolder = try #require(item("Choose Traces Folder…", in: fileMenu))
    #expect(chooseFolder.action == #selector(MainMenuCoordinating.chooseTracesFolder(_:)))
    #expect(chooseFolder.keyEquivalent == "o")
    #expect(chooseFolder.keyEquivalentModifierMask.contains(.command))
    #expect(chooseFolder.target === coordinator)

    let openFolder = try #require(item("Open Traces Folder in Finder", in: fileMenu))
    #expect(openFolder.action == #selector(MainMenuCoordinating.openTracesFolder(_:)))
    #expect(openFolder.keyEquivalent == "O")
    #expect(openFolder.keyEquivalentModifierMask.contains(.command))
    #expect(openFolder.keyEquivalentModifierMask.contains(.shift))
    #expect(openFolder.target === coordinator)

    let watch = try #require(item("Watch Traces Folder", in: viewMenu))
    #expect(watch.action == #selector(MainMenuCoordinating.toggleWatchTracesFolder(_:)))
    #expect(watch.keyEquivalent == "w")
    #expect(watch.keyEquivalentModifierMask.contains(.command))
    #expect(watch.keyEquivalentModifierMask.contains(.shift))
    #expect(watch.target === coordinator)

    let crashReports = try #require(item("Reveal Crash Reports in Finder", in: helpMenu))
    #expect(crashReports.action == #selector(MainMenuCoordinating.revealCrashReports(_:)))
    #expect(crashReports.target === coordinator)
  }
}

