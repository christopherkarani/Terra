import Foundation
import TerraTraceKit

enum AppSettings {
  private enum Key {
    static let tracesDirectoryPath = "traceMacApp.tracesDirectoryPath"
    static let watchTracesDirectory = "traceMacApp.watchTracesDirectory"
    static let didCompleteOnboarding = "traceMacApp.didCompleteOnboarding"
    static let crashReportingEnabled = "traceMacApp.crashReportingEnabled"
    static let automaticUpdateChecksEnabled = "traceMacApp.automaticUpdateChecksEnabled"
  }

  private static let defaults: UserDefaults = {
    let ud = UserDefaults.standard
    ud.register(defaults: [
      Key.crashReportingEnabled: false,
      Key.automaticUpdateChecksEnabled: false
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
}
