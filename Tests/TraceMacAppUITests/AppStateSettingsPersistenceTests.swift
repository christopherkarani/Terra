import Foundation
import Testing
@testable import TraceMacAppUI

@MainActor
@Suite("AppState Settings Persistence", .serialized)
struct AppStateSettingsPersistenceTests {
  private enum Key {
    static let tracesDirectoryPath = "traceMacApp.tracesDirectoryPath"
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
    defaults.removeObject(forKey: Key.tracePageSize)
    defaults.removeObject(forKey: Key.timelineMaxEventMarkers)
    defaults.removeObject(forKey: Key.spanEventsRowLimit)
    defaults.removeObject(forKey: Key.timelineZoomScale)
    defaults.removeObject(forKey: Key.runtimeFilter)
    defaults.removeObject(forKey: Key.openClawSourceFilter)
  }

  @Test("AppState loads persisted dashboard controls and filters")
  func appStateLoadsPersistedSettings() throws {
    cleanupDefaults()
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("trace-ui-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    AppSettings.tracesDirectoryURL = tempDirectory
    AppSettings.tracePageSize = 250
    AppSettings.timelineMaxEventMarkers = 1800
    AppSettings.spanEventsRowLimit = 420
    AppSettings.timelineZoomScale = 1.75
    AppSettings.runtimeFilterRawValue = TraceRuntimeFilter.lmStudio.rawValue
    AppSettings.openClawSourceFilterRawValue = OpenClawTraceSourceFilter.gateway.rawValue

    let state = AppState(isWatchFolderFeatureEnabled: { false })
    #expect(state.tracePageSizeSetting == 250)
    #expect(state.timelineMaxEventMarkers == 1800)
    #expect(state.spanEventsRowLimit == 420)
    #expect(abs(state.timelineZoomScale - 1.75) < 0.000_1)
    #expect(state.runtimeFilter == .lmStudio)
    #expect(state.openClawSourceFilter == .gateway)

    cleanupDefaults()
  }

  @Test("AppState writes dashboard controls and filters back to AppSettings")
  func appStatePersistsChangedSettings() throws {
    cleanupDefaults()

    let state = AppState(isWatchFolderFeatureEnabled: { false })
    state.tracePageSizeSetting = 175
    state.timelineMaxEventMarkers = 2200
    state.spanEventsRowLimit = 600
    state.timelineZoomScale = 2.0
    state.runtimeFilter = .ollama
    state.openClawSourceFilter = .diagnostics

    #expect(AppSettings.tracePageSize == 175)
    #expect(AppSettings.timelineMaxEventMarkers == 2200)
    #expect(AppSettings.spanEventsRowLimit == 600)
    #expect(abs(AppSettings.timelineZoomScale - 2.0) < 0.000_1)
    #expect(AppSettings.runtimeFilterRawValue == TraceRuntimeFilter.ollama.rawValue)
    #expect(AppSettings.openClawSourceFilterRawValue == OpenClawTraceSourceFilter.diagnostics.rawValue)

    state.tracePageSizeSetting = 1
    state.timelineMaxEventMarkers = 1
    state.spanEventsRowLimit = 1
    state.timelineZoomScale = 99

    #expect(state.tracePageSizeSetting == AppSettings.tracePageSizeRange.lowerBound)
    #expect(state.timelineMaxEventMarkers == AppSettings.timelineMaxEventMarkersRange.lowerBound)
    #expect(state.spanEventsRowLimit == AppSettings.spanEventsRowLimitRange.lowerBound)
    #expect(state.timelineZoomScale == CGFloat(AppSettings.timelineZoomScaleRange.upperBound))

    cleanupDefaults()
  }
}
