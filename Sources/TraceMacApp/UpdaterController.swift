import AppKit

#if canImport(Sparkle)
  import Sparkle

  @MainActor
  final class UpdaterController: NSObject {
    private let controller: SPUStandardUpdaterController

    var isAvailable: Bool { true }

    override init() {
      controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
      super.init()
      setAutomaticChecksEnabled(AppSettings.isAutomaticUpdateChecksEnabled)
    }

    func checkForUpdates(_ sender: Any?) {
      controller.checkForUpdates(sender)
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
      controller.updater.automaticallyChecksForUpdates = enabled
    }
  }
#else
  @MainActor
  final class UpdaterController: NSObject {
    var isAvailable: Bool { false }

    func checkForUpdates(_ sender: Any?) {}

    func setAutomaticChecksEnabled(_ enabled: Bool) {}
  }
#endif

