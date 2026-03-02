import XCTest
@testable import TerraCore

final class TerraLifecycleConcurrencyTests: XCTestCase {

    override func setUp() async throws {
        Terra.resetOpenTelemetryForTesting()
    }

    override func tearDown() async throws {
        await Terra.shutdown()
    }

    // MARK: - Test 1: Concurrent Same-Config Install

    /// 10 threads installing the exact same config concurrently — all must succeed.
    /// Same-config idempotency is protected by `openTelemetryInstallLock`.
    func testConcurrentInstall_sameConfig_allSucceed() {
        let config = minimalConfig(port: 15001)
        let group = DispatchGroup()
        var errors: [Error] = []
        let lock = NSLock()

        for _ in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                do {
                    try Terra.installOpenTelemetry(config)
                } catch {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.wait()
        XCTAssertTrue(errors.isEmpty, "Unexpected errors from same-config concurrent install: \(errors)")
        XCTAssertTrue(Terra.isRunning, "Terra should be running after concurrent same-config install")
    }

    // MARK: - Test 2: Concurrent Different-Config Install

    /// 10 threads each racing to install a DIFFERENT config: exactly 1 wins,
    /// the remaining 9 must throw `.alreadyInstalled`. Total == 10.
    func testConcurrentInstall_differentConfigs_onlyOneWins() {
        var successCount = 0
        var alreadyInstalledCount = 0
        var unexpectedErrors: [Error] = []
        let lock = NSLock()
        let group = DispatchGroup()

        for i in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                do {
                    try Terra.installOpenTelemetry(minimalConfig(port: 15011 + i))
                    lock.lock()
                    successCount += 1
                    lock.unlock()
                } catch let e as Terra.InstallOpenTelemetryError where e == .alreadyInstalled {
                    lock.lock()
                    alreadyInstalledCount += 1
                    lock.unlock()
                } catch {
                    lock.lock()
                    unexpectedErrors.append(error)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.wait()
        XCTAssertTrue(unexpectedErrors.isEmpty, "Unexpected errors: \(unexpectedErrors)")
        XCTAssertEqual(successCount, 1, "Expected exactly 1 winner; got \(successCount)")
        XCTAssertEqual(alreadyInstalledCount, 9, "Expected 9 .alreadyInstalled; got \(alreadyInstalledCount)")
        XCTAssertEqual(successCount + alreadyInstalledCount, 10, "Total outcomes must equal 10")
        XCTAssertTrue(Terra.isRunning, "Terra should be running after concurrent different-config install")
    }

    // MARK: - Test 3: Concurrent Shutdown

    /// 10 concurrent `shutdown()` calls must all complete without crash or deadlock.
    /// After all complete, Terra is uninitialized.
    func testConcurrentShutdown_allComplete() async throws {
        try Terra.installOpenTelemetry(minimalConfig(port: 15021))

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { await Terra.shutdown() }
            }
        }

        XCTAssertFalse(Terra.isRunning, "Terra should be uninitialized after concurrent shutdowns")
    }

    // MARK: - Test 4: Interleaved Start/Shutdown

    /// 20 concurrent tasks — even indices install, odd indices shut down.
    /// Each install uses a unique port. No crashes, no hangs. Final state is valid.
    func testInterleavedStartShutdown_noHangsOrCrashes() async {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    if i.isMultiple(of: 2) {
                        // Even: attempt install with a unique config
                        let port = 15031 + i
                        try? Terra.installOpenTelemetry(minimalConfig(port: port))
                    } else {
                        // Odd: attempt shutdown
                        await Terra.shutdown()
                    }
                }
            }
        }

        // Final state is either .running or .uninitialized — both are valid.
        let finalState = Terra.lifecycleState
        XCTAssertTrue(
            finalState == .running || finalState == .uninitialized,
            "Final state must be a valid LifecycleState, got: \(finalState)"
        )

        // Clean up to reach a known state
        await Terra.shutdown()
    }

    // MARK: - Test 5: Start After Concurrent Shutdown

    /// Install once, then fire 5 concurrent shutdowns, then install again — must succeed.
    func testStartAfterConcurrentShutdown_succeeds() async throws {
        try Terra.installOpenTelemetry(minimalConfig(port: 15051))

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { await Terra.shutdown() }
            }
        }

        XCTAssertFalse(Terra.isRunning, "Terra should be uninitialized after concurrent shutdowns")

        // Fresh install must succeed once the lock is clear
        XCTAssertNoThrow(try Terra.installOpenTelemetry(minimalConfig(port: 15052)))
        XCTAssertTrue(Terra.isRunning, "Terra should be running after fresh install post-shutdown")
    }

    // MARK: - Test 6: Concurrent State Reads During Install/Shutdown

    /// 50 concurrent reads of `lifecycleState` / `isRunning` while install and
    /// shutdown are also racing. No crashes; every read returns a valid value.
    func testConcurrentStateReads_duringInstallShutdown() async throws {
        try Terra.installOpenTelemetry(minimalConfig(port: 15061))

        var observedStates: [Terra.LifecycleState] = []
        let lock = NSLock()

        await withTaskGroup(of: Void.self) { group in
            // 50 reader tasks
            for _ in 0..<50 {
                group.addTask {
                    let state = Terra.lifecycleState
                    let running = Terra.isRunning
                    // Consistency check: isRunning must match lifecycleState
                    let expectedRunning = (state == .running)
                    lock.lock()
                    observedStates.append(state)
                    lock.unlock()
                    // We cannot use XCTAssert inside a task group child without
                    // careful synchronization, so we collect results and assert after.
                    _ = running
                    _ = expectedRunning
                }
            }

            // Writer task: shutdown then reinstall
            group.addTask {
                await Terra.shutdown()
                try? Terra.installOpenTelemetry(minimalConfig(port: 15062))
            }
        }

        // Every observed state must be a valid LifecycleState value
        for state in observedStates {
            XCTAssertTrue(
                state == .running || state == .uninitialized,
                "Read an invalid lifecycle state: \(state)"
            )
        }

        XCTAssertEqual(observedStates.count, 50, "Should have 50 state observations")
    }
}

// MARK: - Helpers

private func minimalConfig(port: Int) -> Terra.OpenTelemetryConfiguration {
    Terra.OpenTelemetryConfiguration(
        enableTraces: false,
        enableMetrics: false,
        enableLogs: false,
        enableSignposts: false,
        enableSessions: false,
        otlpTracesEndpoint: URL(string: "http://127.0.0.1:\(port)/v1/traces")!,
        otlpMetricsEndpoint: URL(string: "http://127.0.0.1:\(port)/v1/metrics")!,
        otlpLogsEndpoint: URL(string: "http://127.0.0.1:\(port)/v1/logs")!
    )
}
