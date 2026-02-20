import AppKit
import SwiftUI
import TerraTraceKit

@MainActor
public final class AppCoordinator: NSObject, MainMenuCoordinating {
  private let window: NSWindow
  private let appState: AppState
  private let toolbarProvider: TraceToolbarProvider

  private var onboardingWindowController: OnboardingWindowController?
  private var quickstartWindowController: QuickstartWindowController?
  private let licenseManager: LicenseManager
  private let updaterController = UpdaterController()

  public override init() {
    let licenseManager = LicenseManager()
    self.licenseManager = licenseManager
    self.appState = AppState(isWatchFolderFeatureEnabled: {
      licenseManager.isFeatureEnabled(.watchFolder)
    })
    toolbarProvider = TraceToolbarProvider()
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1200, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Terra Trace Viewer"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true

    let hosting = NSHostingController(
      rootView: DashboardView().environment(appState)
    )
    window.contentViewController = hosting
    window.isReleasedWhenClosed = false
    window.backgroundColor = .windowBackgroundColor

    let toolbar = NSToolbar(identifier: NSToolbar.Identifier("TraceToolbar"))
    toolbar.delegate = toolbarProvider
    toolbar.displayMode = .default
    toolbar.allowsUserCustomization = false
    window.toolbar = toolbar
    window.toolbarStyle = .unifiedCompact

    toolbarProvider.onSearchChange = { [weak appState] query in
      appState?.searchQuery = query
    }
    toolbarProvider.onReload = { [weak appState] in
      appState?.loadTraces()
    }

    super.init()
    MainMenuBuilder.install(coordinator: self)
    updateWindowTitle()
  }

  public func start() {
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    Task { await AppLog.shared.info("app.start") }
    Task {
      await licenseManager.refresh()
      updateWindowTitle()
    }

    if !AppSettings.didCompleteOnboarding {
      showOnboarding()
    }
  }

  @objc public func reloadTraces(_ sender: Any? = nil) {
    appState.loadTraces()
  }

  @objc public func openTracesFolder(_ sender: Any? = nil) {
    let url = AppSettings.tracesDirectoryURL
    Task { await AppLog.shared.info("traces.open_folder path=\(url.path)") }
    do {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    } catch {
      presentErrorAlert(message: "Could not create traces folder.", error: error)
      return
    }
    NSWorkspace.shared.open(url)
  }

  @objc public func chooseTracesFolder(_ sender: Any? = nil) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "Use This Folder"
    panel.directoryURL = AppSettings.tracesDirectoryURL

    panel.beginSheetModal(for: window) { [weak self] response in
      guard let self else { return }
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor in
        await AppLog.shared.info("traces.choose_folder path=\(url.path)")
        self.appState.configureTracesDirectory(url)
      }
    }
  }

  @objc public func toggleWatchTracesFolder(_ sender: Any? = nil) {
    guard licenseManager.isFeatureEnabled(.watchFolder) else {
      presentActivationRequiredAlert(featureName: "Watch Folder")
      return
    }
    Task { await AppLog.shared.info("traces.toggle_watch enabled=\(!AppSettings.isWatchingTracesDirectory)") }
    if AppSettings.isWatchingTracesDirectory {
      appState.stopWatching()
    } else {
      appState.startWatching()
    }
  }

  @objc public func loadSampleTraces(_ sender: Any? = nil) {
    Task { await AppLog.shared.info("traces.load_sample") }
    appState.loadSampleTraces()
  }

  @objc public func showQuickstart(_ sender: Any? = nil) {
    if quickstartWindowController == nil {
      quickstartWindowController = QuickstartWindowController()
    }
    quickstartWindowController?.showWindow(nil)
    quickstartWindowController?.window?.makeKeyAndOrderFront(nil)
  }

  @objc public func checkForUpdates(_ sender: Any? = nil) {
    Task { await AppLog.shared.info("updates.check") }

    guard updaterController.isAvailable else {
      presentErrorAlert(
        message: "Updates are not available in this build.",
        error: CocoaError(.featureUnsupported)
      )
      return
    }

    let feedURLString = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    if feedURLString?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
      presentErrorAlert(
        message: "Updates are not configured.",
        error: CocoaError(.fileNoSuchFile)
      )
      return
    }

    updaterController.checkForUpdates(sender)
  }

  @objc public func exportDiagnostics(_ sender: Any? = nil) {
    Task { await AppLog.shared.info("export.diagnostics") }
    DiagnosticsExporter.export(from: window, tracesDirectoryURL: AppSettings.tracesDirectoryURL, licenseStatus: licenseManager.status)
  }

  @objc public func openPrivacyPolicy(_ sender: Any? = nil) {
    guard let url = LegalDocs.privacyPolicyURL() else {
      presentErrorAlert(message: "Privacy Policy URL is not configured.", error: CocoaError(.fileNoSuchFile))
      return
    }
    NSWorkspace.shared.open(url)
  }

  @objc public func openEULA(_ sender: Any? = nil) {
    guard let url = LegalDocs.eulaURL() else {
      presentErrorAlert(message: "EULA URL is not configured.", error: CocoaError(.fileNoSuchFile))
      return
    }
    NSWorkspace.shared.open(url)
  }

  @objc public func toggleCrashReporting(_ sender: Any? = nil) {
    AppSettings.isCrashReportingEnabled.toggle()
    Task { await AppLog.shared.info("privacy.toggle_crash_reporting enabled=\(AppSettings.isCrashReportingEnabled)") }
  }

  @objc public func toggleAutomaticUpdateChecks(_ sender: Any? = nil) {
    AppSettings.isAutomaticUpdateChecksEnabled.toggle()
    Task { await AppLog.shared.info("privacy.toggle_auto_update_checks enabled=\(AppSettings.isAutomaticUpdateChecksEnabled)") }
    updaterController.setAutomaticChecksEnabled(AppSettings.isAutomaticUpdateChecksEnabled)
  }

  @objc public func revealCrashReports(_ sender: Any? = nil) {
    let url = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Logs", isDirectory: true)
      .appendingPathComponent("DiagnosticReports", isDirectory: true)
    NSWorkspace.shared.open(url)
  }

  private func showOnboarding() {
    if onboardingWindowController != nil { return }

    let controller = OnboardingWindowController(
      actions: .init(
        openTracesFolder: { [weak self] in self?.openTracesFolder(nil) },
        chooseTracesFolder: { [weak self] in self?.chooseTracesFolder(nil) },
        loadSampleTraces: { [weak self] in self?.loadSampleTraces(nil) },
        toggleWatchFolder: { [weak self] in self?.toggleWatchTracesFolder(nil) },
        showQuickstart: { [weak self] in self?.showQuickstart(nil) },
        complete: { [weak self] in
          AppSettings.didCompleteOnboarding = true
          self?.onboardingWindowController?.close()
          self?.onboardingWindowController = nil
        }
      )
    )
    onboardingWindowController = controller
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
  }

  @objc public func activateLicense(_ sender: Any? = nil) {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "Activate TraceMacApp"
    alert.informativeText = "Paste your license key to unlock paid features."

    let field = NSTextField(string: "")
    field.placeholderString = "\(LicenseKey.prefix).<payload>.<signature>"
    field.usesSingleLineMode = true
    field.lineBreakMode = .byTruncatingMiddle
    field.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    field.translatesAutoresizingMaskIntoConstraints = false

    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(field)
    NSLayoutConstraint.activate([
      container.widthAnchor.constraint(equalToConstant: 520),
      field.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      field.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      field.topAnchor.constraint(equalTo: container.topAnchor),
      field.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    alert.accessoryView = container

    alert.addButton(withTitle: "Activate")
    alert.addButton(withTitle: "Cancel")

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self else { return }
      guard response == .alertFirstButtonReturn else { return }
      let key = field.stringValue
      Task { @MainActor in
        do {
          await AppLog.shared.info("license.activate_attempt")
          try await self.licenseManager.activate(licenseKey: key)
          await AppLog.shared.info("license.activate_success")
          self.updateWindowTitle()
        } catch {
          await AppLog.shared.error("license.activate_failed error=\(String(describing: error))")
          self.presentLicenseErrorAlert(error)
        }
      }
    }
  }

  @objc public func deactivateLicense(_ sender: Any? = nil) {
    guard case .licensed = licenseManager.status else { return }

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Deactivate license?"
    alert.informativeText = "This will remove your license key from this Mac."
    alert.addButton(withTitle: "Deactivate")
    alert.addButton(withTitle: "Cancel")

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self else { return }
      guard response == .alertFirstButtonReturn else { return }
      Task { @MainActor in
        do {
          try await self.licenseManager.deactivate()
          await AppLog.shared.info("license.deactivate")
          self.updateWindowTitle()
        } catch {
          self.presentErrorAlert(message: "Could not deactivate license.", error: error)
        }
      }
    }
  }

  @objc public func showLicenseStatus(_ sender: Any? = nil) {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "License Status"
    alert.informativeText = licenseStatusText()
    alert.addButton(withTitle: "OK")
    alert.beginSheetModal(for: window)
  }

  private func presentErrorAlert(message: String, error: Error) {
    Task { await AppLog.shared.error("ui.alert message=\(message) error=\(String(describing: error))") }
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = message
    alert.informativeText = error.localizedDescription
    alert.beginSheetModal(for: window)
  }

  private func updateWindowTitle() {
    let base = "Terra Trace Viewer"
    window.title = "\(base)\(windowTitleSuffix())"
  }

  private func windowTitleSuffix() -> String {
    switch licenseManager.status {
    case .licensed(let verified):
      if verified.isInGrace {
        return " — Licensed (Grace)"
      }
      return " — Licensed"
    case .trial(let daysRemaining, _):
      return " — Trial (\(daysRemaining)d left)"
    case .expiredTrial:
      return " — Trial ended"
    }
  }

  private func licenseStatusText() -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short

    switch licenseManager.status {
    case .licensed(let verified):
      var lines: [String] = [
        "Licensed to: \(verified.payload.licensee)"
      ]
      if let email = verified.payload.email {
        lines.append("Email: \(email)")
      }
      if let expiresAt = verified.payload.expiresAt {
        lines.append("Expires: \(formatter.string(from: expiresAt))")
        if verified.isInGrace {
          lines.append("Status: Grace period")
        }
      } else {
        lines.append("Expires: Never")
      }
      return lines.joined(separator: "\n")
    case .trial(let daysRemaining, let endsAt):
      return "Trial: \(daysRemaining) day(s) remaining\nEnds: \(formatter.string(from: endsAt))"
    case .expiredTrial(let endedAt):
      return "Trial ended: \(formatter.string(from: endedAt))"
    }
  }

  private func presentActivationRequiredAlert(featureName: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "\(featureName) requires activation."
    alert.informativeText = "Activate TraceMacApp to unlock paid features."
    alert.addButton(withTitle: "Activate…")
    alert.addButton(withTitle: "Not Now")
    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self else { return }
      guard response == .alertFirstButtonReturn else { return }
      self.activateLicense(nil)
    }
  }

  private func presentLicenseErrorAlert(_ error: Error) {
    let (title, detail) = describeLicenseError(error)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.informativeText = detail
    alert.beginSheetModal(for: window)
  }

  private func describeLicenseError(_ error: Error) -> (String, String) {
    if let error = error as? LicenseKeyError {
      switch error {
      case .invalidFormat:
        return ("Invalid license key", "The key format should be: \(LicenseKey.prefix).<payload>.<signature>")
      case .invalidPrefix:
        return ("Invalid license key", "This key is not for TraceMacApp.")
      }
    }

    if error is Base64URLError {
      return ("Invalid license key", "The key contains invalid base64url components.")
    }

    if let error = error as? LicenseVerificationError {
      switch error {
      case .notConfigured:
        return (
          "Licensing is not configured",
          "Set `TraceMacAppLicensePublicKey` in Info.plist to your Ed25519 public key to enable activation."
        )
      case .invalidSignature:
        return ("Invalid license key", "The key’s signature did not verify.")
      case .unsupportedVersion:
        return ("Invalid license key", "Unsupported license version.")
      case .wrongBundleIdentifier:
        return ("Invalid license key", "This key is for a different app identifier.")
      case .wrongProduct:
        return ("Invalid license key", "This key is for a different product.")
      case .expired:
        return ("License expired", "Your license has expired (including any offline grace period).")
      }
    }

    return ("Could not activate license", error.localizedDescription)
  }
}

extension AppCoordinator: NSMenuItemValidation {
  public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(toggleWatchTracesFolder(_:)):
      menuItem.state = AppSettings.isWatchingTracesDirectory ? .on : .off
      return true
    case #selector(toggleCrashReporting(_:)):
      menuItem.state = AppSettings.isCrashReportingEnabled ? .on : .off
      return true
    case #selector(toggleAutomaticUpdateChecks(_:)):
      menuItem.state = AppSettings.isAutomaticUpdateChecksEnabled ? .on : .off
      return true
    case #selector(checkForUpdates(_:)):
      let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
      let hasFeedURL = !(feedURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
      return updaterController.isAvailable && hasFeedURL
    case #selector(openPrivacyPolicy(_:)):
      return LegalDocs.privacyPolicyURL() != nil
    case #selector(openEULA(_:)):
      return LegalDocs.eulaURL() != nil
    case #selector(deactivateLicense(_:)):
      return {
        if case .licensed = licenseManager.status { return true }
        return false
      }()
    default:
      return true
    }
  }
}
