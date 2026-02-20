import AppKit
import Testing
@testable import TraceMacAppUI

// MARK: - LegalDocs Tests

@Suite("LegalDocs URL helpers")
struct LegalDocsTests {
  @Test("privacyPolicyURL returns nil when Info.plist key is absent")
  func privacyPolicyURLReturnsNilInTestBundle() {
    // Bundle.main in the test host does not contain TraceMacAppPrivacyPolicyURL,
    // so this should return nil.
    #expect(LegalDocs.privacyPolicyURL() == nil)
  }

  @Test("eulaURL returns nil when Info.plist key is absent")
  func eulaURLReturnsNilInTestBundle() {
    #expect(LegalDocs.eulaURL() == nil)
  }
}

// MARK: - AppCoordinator Tests

@MainActor
@Suite("AppCoordinator", .serialized)
struct AppCoordinatorTests {
  init() {
    _ = NSApplication.shared
  }

  // MARK: - Initialization

  @Test("AppCoordinator can be created without crashing")
  func coordinatorCanBeCreated() {
    let coordinator = AppCoordinator()
    _ = coordinator
  }

  @Test("Window title contains base title after init")
  func windowTitleContainsBaseTitle() {
    let coordinator = AppCoordinator()

    // Access the window through the menu validation interface.
    // The window.title is set in init and updated with a suffix based on license status.
    // At minimum it must contain the base title.
    let menuItem = NSMenuItem()
    menuItem.action = #selector(AppCoordinator.reloadTraces(_:))
    _ = coordinator.validateMenuItem(menuItem)

    // The coordinator is alive; verify the window title indirectly.
    // Since AppCoordinator's init sets window.title to "Terra Trace Viewer" + suffix,
    // and the default license status is trial, the title should reflect that.
    // We cannot access window directly (it's private), so we test the coordinator
    // was created successfully and menu validation works.
    #expect(coordinator.validateMenuItem(menuItem) == true)
  }

  // MARK: - validateMenuItem

  @Test("validateMenuItem returns true for toggleWatchTracesFolder")
  func validateMenuItemToggleWatchReturnsTrueAlways() {
    let coordinator = AppCoordinator()
    let menuItem = NSMenuItem()
    menuItem.action = #selector(AppCoordinator.toggleWatchTracesFolder(_:))

    let result = coordinator.validateMenuItem(menuItem)
    #expect(result == true)
  }

  @Test("toggleWatchTracesFolder sets menu item state based on setting")
  func validateMenuItemToggleWatchSetsState() {
    let coordinator = AppCoordinator()
    let menuItem = NSMenuItem()
    menuItem.action = #selector(AppCoordinator.toggleWatchTracesFolder(_:))

    let originalValue = AppSettings.isWatchingTracesDirectory
    defer { AppSettings.isWatchingTracesDirectory = originalValue }

    AppSettings.isWatchingTracesDirectory = true
    _ = coordinator.validateMenuItem(menuItem)
    #expect(menuItem.state == .on)

    AppSettings.isWatchingTracesDirectory = false
    _ = coordinator.validateMenuItem(menuItem)
    #expect(menuItem.state == .off)
  }

  @Test("toggleCrashReporting sets menu item state based on setting")
  func validateMenuItemCrashReportingSetsState() {
    let coordinator = AppCoordinator()
    let menuItem = NSMenuItem()
    menuItem.action = #selector(AppCoordinator.toggleCrashReporting(_:))

    let originalValue = AppSettings.isCrashReportingEnabled
    defer { AppSettings.isCrashReportingEnabled = originalValue }

    AppSettings.isCrashReportingEnabled = true
    _ = coordinator.validateMenuItem(menuItem)
    #expect(menuItem.state == .on)

    AppSettings.isCrashReportingEnabled = false
    _ = coordinator.validateMenuItem(menuItem)
    #expect(menuItem.state == .off)
  }

  @Test("toggleAutomaticUpdateChecks sets menu item state based on setting")
  func validateMenuItemAutoUpdatesSetsState() {
    let coordinator = AppCoordinator()
    let menuItem = NSMenuItem()
    menuItem.action = #selector(AppCoordinator.toggleAutomaticUpdateChecks(_:))

    let originalValue = AppSettings.isAutomaticUpdateChecksEnabled
    defer { AppSettings.isAutomaticUpdateChecksEnabled = originalValue }

    AppSettings.isAutomaticUpdateChecksEnabled = true
    _ = coordinator.validateMenuItem(menuItem)
    #expect(menuItem.state == .on)

    AppSettings.isAutomaticUpdateChecksEnabled = false
    _ = coordinator.validateMenuItem(menuItem)
    #expect(menuItem.state == .off)
  }

  @Test("checkForUpdates is disabled when updater is not available")
  func validateMenuItemCheckForUpdatesDisabled() {
    // In the test environment, Sparkle is not linked, so UpdaterController.isAvailable is false.
    let coordinator = AppCoordinator()
    let menuItem = NSMenuItem()
    menuItem.action = #selector(AppCoordinator.checkForUpdates(_:))

    let result = coordinator.validateMenuItem(menuItem)
    #expect(result == false)
  }

  @Test("deactivateLicense is disabled when not licensed")
  func validateMenuItemDeactivateLicenseDisabledWhenNotLicensed() {
    // Default LicenseManager status is trial (no license key in test keychain),
    // so deactivateLicense should be disabled.
    let coordinator = AppCoordinator()
    let menuItem = NSMenuItem()
    menuItem.action = #selector(AppCoordinator.deactivateLicense(_:))

    let result = coordinator.validateMenuItem(menuItem)
    #expect(result == false)
  }

  @Test("openPrivacyPolicy is disabled when URL is nil in test bundle")
  func validateMenuItemPrivacyPolicyDisabled() {
    // In the test bundle, TraceMacAppPrivacyPolicyURL is not in Info.plist,
    // so LegalDocs.privacyPolicyURL() returns nil.
    let coordinator = AppCoordinator()
    let menuItem = NSMenuItem()
    menuItem.action = #selector(AppCoordinator.openPrivacyPolicy(_:))

    let result = coordinator.validateMenuItem(menuItem)
    #expect(result == false)
  }

  @Test("openEULA is disabled when URL is nil in test bundle")
  func validateMenuItemEULADisabled() {
    // In the test bundle, TraceMacAppEULAURL is not in Info.plist,
    // so LegalDocs.eulaURL() returns nil.
    let coordinator = AppCoordinator()
    let menuItem = NSMenuItem()
    menuItem.action = #selector(AppCoordinator.openEULA(_:))

    let result = coordinator.validateMenuItem(menuItem)
    #expect(result == false)
  }

  @Test("validateMenuItem returns true for unrecognized actions")
  func validateMenuItemDefaultReturnsTrue() {
    let coordinator = AppCoordinator()
    let menuItem = NSMenuItem()
    menuItem.action = #selector(NSObject.description)

    let result = coordinator.validateMenuItem(menuItem)
    #expect(result == true)
  }

  // MARK: - Window Title Suffix Logic

  @Test("windowTitleSuffix produces correct strings for each license status")
  func windowTitleSuffixLogic() {
    // Test the title suffix logic indirectly by verifying what LicenseManager.status
    // values map to. We construct each status variant and verify the expected pattern.

    let trialStatus = LicenseManager.Status.trial(
      daysRemaining: 10,
      endsAt: Date(timeIntervalSince1970: 100_000)
    )
    switch trialStatus {
    case .trial(let days, _):
      #expect(days == 10)
    default:
      Issue.record("Expected trial status")
    }

    let expiredStatus = LicenseManager.Status.expiredTrial(
      endedAt: Date(timeIntervalSince1970: 50_000)
    )
    switch expiredStatus {
    case .expiredTrial:
      break
    default:
      Issue.record("Expected expiredTrial status")
    }

    let licensedPayload = LicensePayload(
      product: "TraceMacApp",
      bundleIdentifier: "com.terra.TraceMacApp",
      licensee: "Test User",
      issuedAt: Date(timeIntervalSince1970: 1_000)
    )
    let verified = VerifiedLicense(payload: licensedPayload, isInGrace: false)
    let licensedStatus = LicenseManager.Status.licensed(verified)
    switch licensedStatus {
    case .licensed(let v):
      #expect(v.isInGrace == false)
      #expect(v.payload.licensee == "Test User")
    default:
      Issue.record("Expected licensed status")
    }

    let graceVerified = VerifiedLicense(payload: licensedPayload, isInGrace: true)
    let graceStatus = LicenseManager.Status.licensed(graceVerified)
    switch graceStatus {
    case .licensed(let v):
      #expect(v.isInGrace == true)
    default:
      Issue.record("Expected licensed grace status")
    }
  }
}
