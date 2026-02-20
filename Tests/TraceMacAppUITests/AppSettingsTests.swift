import Foundation
import Testing
@testable import TraceMacAppUI

@Suite("AppSettings Tests", .serialized)
struct AppSettingsTests {
  // Keys must match the private Key enum in AppSettings.
  private enum Key {
    static let tracesDirectoryPath = "traceMacApp.tracesDirectoryPath"
    static let crashReportingEnabled = "traceMacApp.crashReportingEnabled"
    static let automaticUpdateChecksEnabled = "traceMacApp.automaticUpdateChecksEnabled"
    static let watchTracesDirectory = "traceMacApp.watchTracesDirectory"
    static let didCompleteOnboarding = "traceMacApp.didCompleteOnboarding"
  }

  private func cleanupDefaults() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: Key.tracesDirectoryPath)
    defaults.removeObject(forKey: Key.crashReportingEnabled)
    defaults.removeObject(forKey: Key.automaticUpdateChecksEnabled)
    defaults.removeObject(forKey: Key.watchTracesDirectory)
    defaults.removeObject(forKey: Key.didCompleteOnboarding)
  }

  @Test("Default tracesDirectoryURL returns a valid URL")
  func defaultTracesDirectoryURLIsValid() {
    cleanupDefaults()
    let url = AppSettings.tracesDirectoryURL
    #expect(!url.path.isEmpty)
    cleanupDefaults()
  }

  @Test("Setting and getting tracesDirectoryURL round-trips")
  func tracesDirectoryURLRoundTrips() {
    cleanupDefaults()
    let customURL = URL(fileURLWithPath: "/tmp/test-traces", isDirectory: true)
    AppSettings.tracesDirectoryURL = customURL
    #expect(AppSettings.tracesDirectoryURL.path == customURL.path)
    cleanupDefaults()
  }

  @Test("Crash reporting defaults to false")
  func crashReportingDefaultsToFalse() {
    cleanupDefaults()
    #expect(AppSettings.isCrashReportingEnabled == false)
    cleanupDefaults()
  }

  @Test("Auto updates defaults to false")
  func autoUpdatesDefaultsToFalse() {
    cleanupDefaults()
    #expect(AppSettings.isAutomaticUpdateChecksEnabled == false)
    cleanupDefaults()
  }

  @Test("Boolean settings round-trip correctly")
  func booleanSettingsRoundTrip() {
    cleanupDefaults()

    AppSettings.isCrashReportingEnabled = true
    #expect(AppSettings.isCrashReportingEnabled == true)

    AppSettings.isAutomaticUpdateChecksEnabled = true
    #expect(AppSettings.isAutomaticUpdateChecksEnabled == true)

    AppSettings.isWatchingTracesDirectory = true
    #expect(AppSettings.isWatchingTracesDirectory == true)

    AppSettings.didCompleteOnboarding = true
    #expect(AppSettings.didCompleteOnboarding == true)

    cleanupDefaults()
  }
}
