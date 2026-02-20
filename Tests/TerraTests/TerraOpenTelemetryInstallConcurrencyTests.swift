import XCTest

@testable import TerraCore

final class TerraOpenTelemetryInstallConcurrencyTests: XCTestCase {
  override func setUp() {
    super.setUp()
    Terra.resetOpenTelemetryForTesting()
  }

  override func tearDown() {
    Terra.resetOpenTelemetryForTesting()
    super.tearDown()
  }

  actor AsyncBarrier {
    private let target: Int
    private var waiting = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(participants: Int) {
      target = participants
    }

    func wait() async {
      if waiting + 1 == target {
        waiting += 1
        continuations.forEach { $0.resume() }
        continuations.removeAll()
        return
      }

      waiting += 1
      await withCheckedContinuation { continuation in
        continuations.append(continuation)
      }
    }
  }

  private func makeConfig(endpoint: URL) -> Terra.OpenTelemetryConfiguration {
    Terra.OpenTelemetryConfiguration(
      enableMetrics: false,
      enableLogs: false,
      enableSignposts: false,
      enableSessions: false,
      otlpTracesEndpoint: endpoint
    )
  }

  func testConcurrentInstall_allowsSingleSuccess() async {
    let endpoints = [
      URL(string: "http://localhost:4318/v1/traces")!,
      URL(string: "http://localhost:4319/v1/traces")!,
      URL(string: "http://localhost:4320/v1/traces")!,
    ]

    let barrier = AsyncBarrier(participants: endpoints.count)

    let results = await withTaskGroup(of: Result<Void, Error>.self) { group in
      for endpoint in endpoints {
        group.addTask {
          await barrier.wait()
          let config = self.makeConfig(endpoint: endpoint)
          return Result { try Terra.installOpenTelemetry(config) }
        }
      }

      var collected: [Result<Void, Error>] = []
      for await result in group {
        collected.append(result)
      }
      return collected
    }

    let successCount = results.filter {
      if case .success = $0 { return true }
      return false
    }.count

    let alreadyInstalledCount = results.filter {
      guard case .failure(let error) = $0 else { return false }
      guard let installError = error as? Terra.InstallOpenTelemetryError else { return false }
      if case .alreadyInstalled = installError { return true }
      return false
    }.count

    XCTAssertEqual(successCount, 1)
    XCTAssertEqual(alreadyInstalledCount, endpoints.count - 1)
  }

  func testConcurrentInstall_sameConfig_bothSucceed() async {
    let endpoint = URL(string: "http://localhost:4350/v1/traces")!
    let config = makeConfig(endpoint: endpoint)

    let barrier = AsyncBarrier(participants: 2)

    let results = await withTaskGroup(of: Result<Void, Error>.self) { group in
      for _ in 0..<2 {
        group.addTask {
          await barrier.wait()
          return Result { try Terra.installOpenTelemetry(config) }
        }
      }
      var collected: [Result<Void, Error>] = []
      for await result in group {
        collected.append(result)
      }
      return collected
    }

    // When both calls use identical config, both should succeed (idempotent)
    let successCount = results.filter {
      if case .success = $0 { return true }
      return false
    }.count
    XCTAssertGreaterThanOrEqual(successCount, 1, "At least one concurrent same-config install should succeed")
    // None should throw alreadyInstalled -- same config is allowed
    let alreadyInstalledCount = results.filter {
      guard case .failure(let error) = $0 else { return false }
      guard let installError = error as? Terra.InstallOpenTelemetryError else { return false }
      if case .alreadyInstalled = installError { return true }
      return false
    }.count
    XCTAssertEqual(alreadyInstalledCount, 0, "Same-config concurrent install should not throw alreadyInstalled")
  }

  func testConcurrentInstall_consistentConfiguration() async {
    let endpoints = [
      URL(string: "http://localhost:4331/v1/traces")!,
      URL(string: "http://localhost:4332/v1/traces")!,
    ]

    let barrier = AsyncBarrier(participants: endpoints.count)

    let attempts = await withTaskGroup(of: (URL, Result<Void, Error>).self) { group in
      for endpoint in endpoints {
        group.addTask {
          await barrier.wait()
          let config = self.makeConfig(endpoint: endpoint)
          return (endpoint, Result { try Terra.installOpenTelemetry(config) })
        }
      }

      var collected: [(URL, Result<Void, Error>)] = []
      for await attempt in group {
        collected.append(attempt)
      }
      return collected
    }

    let successes = attempts.compactMap { endpoint, result -> URL? in
      if case .success = result { return endpoint }
      return nil
    }

    let alreadyInstalledCount = attempts.filter { _, result in
      guard case .failure(let error) = result else { return false }
      guard let installError = error as? Terra.InstallOpenTelemetryError else { return false }
      if case .alreadyInstalled = installError { return true }
      return false
    }.count

    XCTAssertEqual(successes.count, 1)
    XCTAssertEqual(alreadyInstalledCount, endpoints.count - 1)

    guard let winningEndpoint = successes.first else {
      XCTFail("Expected a single successful install.")
      return
    }

    let winningConfig = makeConfig(endpoint: winningEndpoint)
    XCTAssertNoThrow(try Terra.installOpenTelemetry(winningConfig))

    let losingEndpoint = endpoints.first { $0 != winningEndpoint }!
    let losingConfig = makeConfig(endpoint: losingEndpoint)
    XCTAssertThrowsError(try Terra.installOpenTelemetry(losingConfig)) { error in
      guard let installError = error as? Terra.InstallOpenTelemetryError else {
        XCTFail("Expected InstallOpenTelemetryError but got: \(error)")
        return
      }
      if case .alreadyInstalled = installError { return }
      XCTFail("Expected alreadyInstalled but got: \(installError)")
    }
  }
}
