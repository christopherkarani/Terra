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
  }

  static let defaultOTLPReceiverPort: UInt16 = 4318

  private static let defaults: UserDefaults = {
    let ud = UserDefaults.standard
    ud.register(defaults: [
      Key.crashReportingEnabled: false,
      Key.automaticUpdateChecksEnabled: false,
      Key.traceRetentionDays: 30,
      Key.otlpReceiverEnabled: false,
      Key.otlpReceiverPort: Int(defaultOTLPReceiverPort)
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
}
