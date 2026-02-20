import Foundation
import TerraTraceKit

enum AppSettings {
  private enum Key {
    static let tracesDirectoryPath = "traceMacApp.tracesDirectoryPath"
    static let watchTracesDirectory = "traceMacApp.watchTracesDirectory"
    static let didCompleteOnboarding = "traceMacApp.didCompleteOnboarding"
    static let crashReportingEnabled = "traceMacApp.crashReportingEnabled"
    static let automaticUpdateChecksEnabled = "traceMacApp.automaticUpdateChecksEnabled"
    static let traceRetentionDays = "traceMacApp.traceRetentionDays"
    static let otlpReceiverEnabled = "traceMacApp.otlpReceiverEnabled"
    static let otlpReceiverPort = "traceMacApp.otlpReceiverPort"
    static let tracePageSize = "traceMacApp.tracePageSize"
    static let timelineMaxEventMarkers = "traceMacApp.timelineMaxEventMarkers"
    static let spanEventsRowLimit = "traceMacApp.spanEventsRowLimit"
    static let timelineZoomScale = "traceMacApp.timelineZoomScale"
    static let runtimeFilter = "traceMacApp.runtimeFilter"
    static let openClawSourceFilter = "traceMacApp.openClawSourceFilter"
    static let openClawGatewayCaptureEnabled = "traceMacApp.openClawGatewayCaptureEnabled"
    static let openClawTransparentModeEnabled = "traceMacApp.openClawTransparentModeEnabled"
    static let openClawGatewayEndpoint = "traceMacApp.openClawGatewayEndpoint"
    static let openClawGatewayAuthMode = "traceMacApp.openClawGatewayAuthMode"
    static let openClawGatewayBearerToken = "traceMacApp.openClawGatewayBearerToken"
  }

  static let defaultOTLPReceiverPort: UInt16 = 4318
  static let defaultTracePageSize: Int = 100
  static let defaultTimelineMaxEventMarkers: Int = 1200
  static let defaultSpanEventsRowLimit: Int = 300
  static let defaultTimelineZoomScale: Double = 1.0

  static let tracePageSizeRange: ClosedRange<Int> = 25...5_000
  static let timelineMaxEventMarkersRange: ClosedRange<Int> = 200...25_000
  static let spanEventsRowLimitRange: ClosedRange<Int> = 25...10_000
  static let timelineZoomScaleRange: ClosedRange<Double> = 0.5...5.0

  private static let defaults: UserDefaults = {
    let ud = UserDefaults.standard
    ud.register(defaults: [
      Key.crashReportingEnabled: false,
      Key.automaticUpdateChecksEnabled: false,
      Key.traceRetentionDays: 30,
      Key.otlpReceiverEnabled: false,
      Key.otlpReceiverPort: Int(defaultOTLPReceiverPort),
      Key.tracePageSize: defaultTracePageSize,
      Key.timelineMaxEventMarkers: defaultTimelineMaxEventMarkers,
      Key.spanEventsRowLimit: defaultSpanEventsRowLimit,
      Key.timelineZoomScale: defaultTimelineZoomScale,
      Key.runtimeFilter: TraceRuntimeFilter.all.rawValue,
      Key.openClawSourceFilter: OpenClawTraceSourceFilter.all.rawValue,
      Key.openClawGatewayCaptureEnabled: false,
      Key.openClawTransparentModeEnabled: false,
      Key.openClawGatewayEndpoint: "http://localhost:3000/v1/chat/completions",
      Key.openClawGatewayAuthMode: "none",
      Key.openClawGatewayBearerToken: ""
    ])
    return ud
  }()

  static var tracesDirectoryURL: URL {
    get {
      if
        let path = defaults.string(forKey: Key.tracesDirectoryPath),
        !path.isEmpty
      {
        return URL(fileURLWithPath: path, isDirectory: true)
      }
      return TraceFileLocator.defaultTracesDirectoryURL()
    }
    set {
      defaults.set(newValue.path, forKey: Key.tracesDirectoryPath)
    }
  }

  static var isWatchingTracesDirectory: Bool {
    get { defaults.bool(forKey: Key.watchTracesDirectory) }
    set { defaults.set(newValue, forKey: Key.watchTracesDirectory) }
  }

  static var didCompleteOnboarding: Bool {
    get { defaults.bool(forKey: Key.didCompleteOnboarding) }
    set { defaults.set(newValue, forKey: Key.didCompleteOnboarding) }
  }

  static var isCrashReportingEnabled: Bool {
    get { defaults.bool(forKey: Key.crashReportingEnabled) }
    set { defaults.set(newValue, forKey: Key.crashReportingEnabled) }
  }

  static var isAutomaticUpdateChecksEnabled: Bool {
    get { defaults.bool(forKey: Key.automaticUpdateChecksEnabled) }
    set { defaults.set(newValue, forKey: Key.automaticUpdateChecksEnabled) }
  }

  static var traceRetentionDays: Int {
    get { defaults.integer(forKey: Key.traceRetentionDays) }
    set { defaults.set(newValue, forKey: Key.traceRetentionDays) }
  }

  static var isOTLPReceiverEnabled: Bool {
    get { defaults.bool(forKey: Key.otlpReceiverEnabled) }
    set { defaults.set(newValue, forKey: Key.otlpReceiverEnabled) }
  }

  static var otlpReceiverPort: UInt16 {
    get {
      let value = defaults.integer(forKey: Key.otlpReceiverPort)
      return value > 0 ? UInt16(clamping: value) : defaultOTLPReceiverPort
    }
    set { defaults.set(Int(newValue), forKey: Key.otlpReceiverPort) }
  }

  static var tracePageSize: Int {
    get {
      let value = defaults.integer(forKey: Key.tracePageSize)
      return clampedInt(
        value > 0 ? value : defaultTracePageSize,
        range: tracePageSizeRange
      )
    }
    set {
      defaults.set(clampedInt(newValue, range: tracePageSizeRange), forKey: Key.tracePageSize)
    }
  }

  static var timelineMaxEventMarkers: Int {
    get {
      let value = defaults.integer(forKey: Key.timelineMaxEventMarkers)
      return clampedInt(
        value > 0 ? value : defaultTimelineMaxEventMarkers,
        range: timelineMaxEventMarkersRange
      )
    }
    set {
      defaults.set(
        clampedInt(newValue, range: timelineMaxEventMarkersRange),
        forKey: Key.timelineMaxEventMarkers
      )
    }
  }

  static var spanEventsRowLimit: Int {
    get {
      let value = defaults.integer(forKey: Key.spanEventsRowLimit)
      return clampedInt(
        value > 0 ? value : defaultSpanEventsRowLimit,
        range: spanEventsRowLimitRange
      )
    }
    set {
      defaults.set(clampedInt(newValue, range: spanEventsRowLimitRange), forKey: Key.spanEventsRowLimit)
    }
  }

  static var timelineZoomScale: CGFloat {
    get {
      let value = defaults.double(forKey: Key.timelineZoomScale)
      let safeValue = value > 0 ? value : defaultTimelineZoomScale
      return CGFloat(clampedDouble(safeValue, range: timelineZoomScaleRange))
    }
    set {
      let clamped = clampedDouble(Double(newValue), range: timelineZoomScaleRange)
      defaults.set(clamped, forKey: Key.timelineZoomScale)
    }
  }

  static var runtimeFilterRawValue: String {
    get { defaults.string(forKey: Key.runtimeFilter) ?? TraceRuntimeFilter.all.rawValue }
    set { defaults.set(newValue, forKey: Key.runtimeFilter) }
  }

  static var openClawSourceFilterRawValue: String {
    get { defaults.string(forKey: Key.openClawSourceFilter) ?? OpenClawTraceSourceFilter.all.rawValue }
    set { defaults.set(newValue, forKey: Key.openClawSourceFilter) }
  }

  static var isOpenClawGatewayCaptureEnabled: Bool {
    get { defaults.bool(forKey: Key.openClawGatewayCaptureEnabled) }
    set { defaults.set(newValue, forKey: Key.openClawGatewayCaptureEnabled) }
  }

  static var isOpenClawTransparentModeEnabled: Bool {
    get { defaults.bool(forKey: Key.openClawTransparentModeEnabled) }
    set { defaults.set(newValue, forKey: Key.openClawTransparentModeEnabled) }
  }

  static var openClawGatewayEndpoint: String {
    get { defaults.string(forKey: Key.openClawGatewayEndpoint) ?? "http://localhost:3000/v1/chat/completions" }
    set { defaults.set(newValue, forKey: Key.openClawGatewayEndpoint) }
  }

  static var openClawGatewayAuthMode: String {
    get { defaults.string(forKey: Key.openClawGatewayAuthMode) ?? "none" }
    set { defaults.set(newValue, forKey: Key.openClawGatewayAuthMode) }
  }

  static var openClawGatewayBearerToken: String {
    get { defaults.string(forKey: Key.openClawGatewayBearerToken) ?? "" }
    set { defaults.set(newValue, forKey: Key.openClawGatewayBearerToken) }
  }

  /// ~/Library/Logs/ai.openclaw.mac/ — where OpenClaw writes diagnostics output.
  static var openClawDiagnosticsDirectoryURL: URL {
    let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
    return base
        .appendingPathComponent("Logs", isDirectory: true)
        .appendingPathComponent("ai.openclaw.mac", isDirectory: true)
  }

  /// Returns true for OpenClaw diagnostic file names:
  /// diagnostics.jsonl, gateway.log, openclaw-YYYY-MM-DD.log
  static func isSupportedOpenClawTraceFileName(_ name: String) -> Bool {
    if name == "diagnostics.jsonl" || name == "gateway.log" { return true }
    let pattern = #"^openclaw-\d{4}-\d{2}-\d{2}\.log$"#
    return name.range(of: pattern, options: .regularExpression) != nil
  }

  private static func clampedInt(_ value: Int, range: ClosedRange<Int>) -> Int {
    min(max(value, range.lowerBound), range.upperBound)
  }

  private static func clampedDouble(_ value: Double, range: ClosedRange<Double>) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
  }
}
