import Testing
@testable import Terra
@testable import TerraCore

@Suite("Terra lifecycle public API", .serialized)
final class TerraLifecycleAPITests {
  init() {
    Terra.lockTestingIsolation()
    Terra.resetOpenTelemetryForTesting()
  }

  deinit {
    Terra.resetOpenTelemetryForTesting()
    Terra.unlockTestingIsolation()
  }

  @Test("start/shutdown transitions lifecycle state deterministically")
  func startShutdownTransitions() async throws {
    Terra.resetOpenTelemetryForTesting()
    await Terra.reset()

    #expect(Terra.lifecycleState == .stopped)
    #expect(!Terra.isRunning)

    var config = Terra.Configuration()
    config.instrumentations = .none
    config.enableSignposts = false
    config.enableSessions = false
    try await Terra.start(config)

    #expect(Terra.lifecycleState == .running)
    #expect(Terra.isRunning)

    await Terra.shutdown()

    #expect(Terra.lifecycleState == .stopped)
    #expect(!Terra.isRunning)
  }

  @Test("reset is idempotent and leaves Terra uninitialized")
  func resetIsIdempotent() async {
    Terra.resetOpenTelemetryForTesting()
    await Terra.reset()

    await Terra.reset()
    await Terra.reset()

    #expect(Terra.lifecycleState == .stopped)
    #expect(!Terra.isRunning)
  }

  @Test("reconfigure restarts and allows a different configuration")
  func reconfigureAllowsDifferentConfig() async throws {
    Terra.resetOpenTelemetryForTesting()
    await Terra.reset()

    var config1 = Terra.Configuration()
    config1.instrumentations = .none
    config1.enableSignposts = false
    config1.enableSessions = false
    try await Terra.start(config1)

    var config2 = config1
    config2.serviceName = "com.example.changed"
    try await Terra.reconfigure(config2)

    // Same-config start is idempotent.
    try await Terra.start(config2)

    // Different-config start must throw without an explicit reconfigure.
    do {
      try await Terra.start(config1)
      #expect(Bool(false), "Expected Terra.start to throw already_started when called with a different config while running.")
    } catch let error as Terra.TerraError {
      #expect(error.code == .already_started)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test("concurrent start/shutdown/reconfigure tasks do not deadlock")
  func concurrentLifecycleOpsDoNotDeadlock() async {
    Terra.resetOpenTelemetryForTesting()
    await Terra.reset()

    var base = Terra.Configuration()
    base.instrumentations = .none
    base.enableSignposts = false
    base.enableSessions = false

    await withTaskGroup(of: Void.self) { group in
      for i in 0..<30 {
        group.addTask {
          switch i % 3 {
          case 0:
            try? await Terra.start(base)
          case 1:
            await Terra.shutdown()
          default:
            var config = base
            config.serviceName = "com.example.\(i)"
            try? await Terra.reconfigure(config)
          }
        }
      }
    }

    #expect(Terra.lifecycleState == .running || Terra.lifecycleState == .stopped)
    await Terra.shutdown()
  }
}
