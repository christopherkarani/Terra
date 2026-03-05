import Foundation
import TerraCore

extension Terra {
  actor _LifecycleController {
    private var activeConfiguration: Terra.Configuration?

    func start(_ config: Terra.Configuration) throws {
      if let activeConfiguration {
        guard activeConfiguration == config else {
          throw Terra.InstallOpenTelemetryError.alreadyInstalled
        }
        return
      }

      try Terra._performStart(config.asAutoInstrumentConfiguration())
      activeConfiguration = config
    }

    func shutdown() {
      activeConfiguration = nil
      Terra._disableAutoInstrumentationsForShutdown()
      Terra._shutdownOpenTelemetry()
    }

    func reconfigure(_ config: Terra.Configuration) throws {
      shutdown()
      try start(config)
    }

    func reset() {
      shutdown()
    }
  }

  static let _lifecycleController = _LifecycleController()

  /// The current lifecycle state of the Terra runtime.
  public static var lifecycleState: Terra.LifecycleState {
    _lifecycleState
  }

  /// `true` when Terra has been started and is actively collecting telemetry.
  public static var isRunning: Bool {
    _isRunning
  }

  /// Shuts down Terra gracefully.
  ///
  /// Safe to call from any context. Idempotent — calling it when Terra is not
  /// running is a no-op.
  public static func shutdown() async {
    await _lifecycleController.shutdown()
  }

  /// Shuts down Terra and clears any cached lifecycle configuration.
  ///
  /// After this call, `Terra.start(...)` may be called again with any configuration.
  public static func reset() async {
    await _lifecycleController.reset()
  }

  /// Restarts Terra with a new configuration.
  ///
  /// Deterministic semantics: `reconfigure` always performs a shutdown then a fresh
  /// start. If Terra is not running, this behaves like `start`.
  public static func reconfigure(_ config: Terra.Configuration) async throws {
    try await _lifecycleController.reconfigure(config)
  }
}
