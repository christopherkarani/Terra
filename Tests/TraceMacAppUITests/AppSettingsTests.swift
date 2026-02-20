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
    static let tracePageSize = "traceMacApp.tracePageSize"
    static let timelineMaxEventMarkers = "traceMacApp.timelineMaxEventMarkers"
    static let spanEventsRowLimit = "traceMacApp.spanEventsRowLimit"
    static let timelineZoomScale = "traceMacApp.timelineZoomScale"
    static let runtimeFilter = "traceMacApp.runtimeFilter"
    static let openClawSourceFilter = "traceMacApp.openClawSourceFilter"
  }

  private func cleanupDefaults() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: Key.tracesDirectoryPath)
    defaults.removeObject(forKey: Key.crashReportingEnabled)
    defaults.removeObject(forKey: Key.automaticUpdateChecksEnabled)
    defaults.removeObject(forKey: Key.watchTracesDirectory)
    defaults.removeObject(forKey: Key.didCompleteOnboarding)
    defaults.removeObject(forKey: Key.tracePageSize)
    defaults.removeObject(forKey: Key.timelineMaxEventMarkers)
    defaults.removeObject(forKey: Key.spanEventsRowLimit)
    defaults.removeObject(forKey: Key.timelineZoomScale)
    defaults.removeObject(forKey: Key.runtimeFilter)
    defaults.removeObject(forKey: Key.openClawSourceFilter)
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

  @Test("Dashboard volume settings clamp and round-trip")
  func dashboardVolumeSettingsRoundTrip() {
    cleanupDefaults()

    AppSettings.tracePageSize = 120
    #expect(AppSettings.tracePageSize == 120)

    AppSettings.tracePageSize = 999_999
    #expect(AppSettings.tracePageSize == AppSettings.tracePageSizeRange.upperBound)

    AppSettings.timelineMaxEventMarkers = 2_500
    #expect(AppSettings.timelineMaxEventMarkers == 2_500)

    AppSettings.spanEventsRowLimit = 640
    #expect(AppSettings.spanEventsRowLimit == 640)

    AppSettings.timelineZoomScale = 1.65
    #expect(abs(AppSettings.timelineZoomScale - 1.65) < 0.000_1)

    cleanupDefaults()
  }

  @Test("Runtime and source filter persistence round-trip")
  func runtimeAndSourceFilterRoundTrip() {
    cleanupDefaults()

    AppSettings.runtimeFilterRawValue = TraceRuntimeFilter.ollama.rawValue
    AppSettings.openClawSourceFilterRawValue = OpenClawTraceSourceFilter.gateway.rawValue

    #expect(AppSettings.runtimeFilterRawValue == TraceRuntimeFilter.ollama.rawValue)
    #expect(AppSettings.openClawSourceFilterRawValue == OpenClawTraceSourceFilter.gateway.rawValue)

    cleanupDefaults()
  }
}
