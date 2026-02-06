import AppKit
import Foundation
import UniformTypeIdentifiers

enum DiagnosticsExporter {
  static func export(from window: NSWindow, tracesDirectoryURL: URL, licenseStatus: LicenseManager.Status) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.zip]
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.nameFieldStringValue = "TraceMacApp-Diagnostics.zip"

    panel.beginSheetModal(for: window) { response in
      guard response == .OK, let destinationURL = panel.url else { return }
      Task { @MainActor in
        do {
          try Self.writeDiagnosticsZip(
            to: destinationURL,
            tracesDirectoryURL: tracesDirectoryURL,
            licenseStatus: licenseStatus
          )
        } catch {
          let alert = NSAlert()
          alert.alertStyle = .warning
          alert.messageText = "Could not export diagnostics."
          alert.informativeText = error.localizedDescription
          alert.beginSheetModal(for: window)
        }
      }
    }
  }

  private static func writeDiagnosticsZip(
    to destinationURL: URL,
    tracesDirectoryURL: URL,
    licenseStatus: LicenseManager.Status
  ) throws {
    let fileManager = FileManager.default
    let tempDir = fileManager.temporaryDirectory
      .appendingPathComponent("TraceMacAppDiagnostics-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: tempDir) }

    let infoURL = tempDir.appendingPathComponent("diagnostics.json", isDirectory: false)
    let info = DiagnosticsInfo(tracesDirectory: tracesDirectoryURL.path, licenseStatus: licenseStatus)
    let data = try JSONEncoder().encode(info)
    try data.write(to: infoURL, options: [.atomic])

    let tracesURL = tempDir.appendingPathComponent("trace_files.json", isDirectory: false)
    let listing = TraceDirectoryListing(files: listTraceFiles(in: tracesDirectoryURL))
    try JSONEncoder().encode(listing).write(to: tracesURL, options: [.atomic])

    let logURL = AppLog.defaultLogFileURL()
    if fileManager.fileExists(atPath: logURL.path) {
      let dest = tempDir.appendingPathComponent("TraceMacApp.log", isDirectory: false)
      try? fileManager.copyItem(at: logURL, to: dest)
    }

    try makeZip(from: tempDir, to: destinationURL)
  }

  private static func listTraceFiles(in directoryURL: URL) -> [TraceFileInfo] {
    let fileManager = FileManager.default
    guard let urls = try? fileManager.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    return urls.compactMap { url in
      let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
      return TraceFileInfo(
        name: url.lastPathComponent,
        sizeBytes: values?.fileSize,
        modifiedAt: values?.contentModificationDate
      )
    }
    .sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
  }

  private static func makeZip(from directoryURL: URL, to destinationURL: URL) throws {
    // Prefer `ditto` (built-in on macOS) to avoid extra dependencies.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", directoryURL.path, destinationURL.path]

    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw CocoaError(.fileWriteUnknown)
    }
  }
}

private struct DiagnosticsInfo: Codable {
  var timestamp: Date
  var appVersion: String?
  var appBuild: String?
  var bundleIdentifier: String?
  var osVersion: String
  var tracesDirectory: String
  var isWatchingTracesDirectory: Bool
  var isCrashReportingEnabled: Bool
  var isAutomaticUpdateChecksEnabled: Bool
  var license: LicenseDiagnostics

  init(tracesDirectory: String, licenseStatus: LicenseManager.Status) {
    self.timestamp = Date()
    self.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    self.appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    self.bundleIdentifier = Bundle.main.bundleIdentifier
    self.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    self.tracesDirectory = tracesDirectory
    self.isWatchingTracesDirectory = AppSettings.isWatchingTracesDirectory
    self.isCrashReportingEnabled = AppSettings.isCrashReportingEnabled
    self.isAutomaticUpdateChecksEnabled = AppSettings.isAutomaticUpdateChecksEnabled
    self.license = LicenseDiagnostics(status: licenseStatus)
  }
}

private struct TraceDirectoryListing: Codable {
  var files: [TraceFileInfo]
}

private struct TraceFileInfo: Codable {
  var name: String
  var sizeBytes: Int?
  var modifiedAt: Date?
}

private struct LicenseDiagnostics: Codable {
  var kind: String
  var licensee: String?
  var email: String?
  var expiresAt: Date?
  var isInGrace: Bool?
  var trialDaysRemaining: Int?
  var trialEndsAt: Date?

  init(status: LicenseManager.Status) {
    switch status {
    case .licensed(let verified):
      kind = "licensed"
      licensee = verified.payload.licensee
      email = verified.payload.email
      expiresAt = verified.payload.expiresAt
      isInGrace = verified.isInGrace
      trialDaysRemaining = nil
      trialEndsAt = nil
    case .trial(let daysRemaining, let endsAt):
      kind = "trial"
      licensee = nil
      email = nil
      expiresAt = nil
      isInGrace = nil
      trialDaysRemaining = daysRemaining
      trialEndsAt = endsAt
    case .expiredTrial:
      kind = "expired_trial"
      licensee = nil
      email = nil
      expiresAt = nil
      isInGrace = nil
      trialDaysRemaining = nil
      trialEndsAt = nil
    }
  }
}
