import Foundation
import TerraCore

extension Terra {
  actor _LifecycleController {
    private var activeConfiguration: Terra.Configuration?

    func start(_ config: Terra.Configuration) throws {
      if let activeConfiguration {
        guard activeConfiguration == config else {
          throw Terra.TerraError(
            code: .already_started,
            message: "Terra is already running with a different configuration.",
            context: [
              "transition": "start",
              "state": "\(Terra._lifecycleState)",
            ]
          )
        }
        return
      }

      guard Terra._lifecycleState == .stopped else {
        throw Terra._invalidLifecycleStateError(
          transition: "start",
          state: Terra._lifecycleState
        )
      }

      do {
        try Terra._validateLifecycleConfiguration(config)
        try Terra._performStart(config.asAutoInstrumentConfiguration())
        activeConfiguration = config
      } catch let error as Terra.TerraError {
        throw error
      } catch {
        throw Terra._mapLifecycleStartError(error, config: config, transition: "start")
      }
    }

    func shutdown() {
      activeConfiguration = nil
      Terra._disableAutoInstrumentationsForShutdown()
      #if canImport(CTerraBridge)
      Terra.shutdownZigBackend()
      #endif
      Terra._shutdownOpenTelemetry()
    }

    func reconfigure(_ config: Terra.Configuration) throws {
      guard activeConfiguration != nil else {
        throw Terra._invalidLifecycleStateError(
          transition: "reconfigure",
          state: Terra._lifecycleState
        )
      }
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
  /// start. Calling it while Terra is not running throws `TerraError` with
  /// `.invalid_lifecycle_state`.
  public static func reconfigure(_ config: Terra.Configuration) async throws {
    try await _lifecycleController.reconfigure(config)
  }
}

extension Terra {
  static func _validateLifecycleConfiguration(_ config: Terra.Configuration) throws {
    // Derive the endpoint URL from the destination enum
    let endpointURL: URL
    switch config.destination {
    case .localDashboard:
      endpointURL = URL(string: "http://127.0.0.1:4318")!
    case .endpoint(let url):
      endpointURL = url
    }

    let scheme = endpointURL.scheme?.lowercased()
    guard
      let scheme,
      scheme == "http" || scheme == "https",
      endpointURL.host != nil
    else {
      throw Terra.TerraError(
        code: .invalid_endpoint,
        message: "Terra.Configuration destination endpoint must use http/https and include a host.",
        context: [
          "endpoint": endpointURL.absoluteString,
        ]
      )
    }
  }

  static func _mapLifecycleStartError(
    _ error: any Error,
    config: Terra.Configuration,
    transition: String
  ) -> Terra.TerraError {
    if let error = error as? Terra.TerraError {
      return error
    }

    if let installError = error as? Terra.InstallOpenTelemetryError, installError == .alreadyInstalled {
      return Terra.TerraError(
        code: .already_started,
        message: "Terra is already running with an existing configuration.",
        context: [
          "transition": transition,
          "state": "\(Terra._lifecycleState)",
        ],
        underlying: error
      )
    }

    if _isPersistenceSetupFailure(error, config: config) {
      var context: [String: String] = ["transition": transition]
      // Extract storage URL from persistence enum for error context
      switch config.persistence {
      case .balanced(let url), .instant(let url):
        context["storage_url"] = url.absoluteString
      case .off:
        break
      }
      return Terra.TerraError(
        code: .persistence_setup_failed,
        message: "Failed to initialize persistence storage.",
        context: context,
        underlying: error
      )
    }

    return Terra.TerraError(
      code: .start_failed,
      message: "Terra failed to start.",
      context: ["transition": transition],
      underlying: error
    )
  }

  static func _invalidLifecycleStateError(
    transition: String,
    state: Terra.LifecycleState
  ) -> Terra.TerraError {
    Terra.TerraError(
      code: .invalid_lifecycle_state,
      message: "Cannot perform '\(transition)' while Terra is in '\(state)' state.",
      context: [
        "transition": transition,
        "state": "\(state)",
      ]
    )
  }

  private static func _isPersistenceSetupFailure(
    _ error: any Error,
    config: Terra.Configuration
  ) -> Bool {
    // Extract storage URL from persistence enum if set
    let persistenceURL: URL?
    switch config.persistence {
    case .off:
      persistenceURL = nil
    case .balanced(let url), .instant(let url):
      persistenceURL = url
    }

    guard persistenceURL != nil else { return false }
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain {
      return true
    }

    let description = String(describing: error).lowercased()
    if description.contains("persistence") || description.contains("storage") {
      return true
    }

    if let path = persistenceURL?.path.lowercased(), !path.isEmpty {
      return description.contains(path)
    }
    return false
  }
}
