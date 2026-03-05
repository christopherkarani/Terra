# Phase 3: Runtime Lifecycle Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add explicit, deterministic lifecycle control (`lifecycleState`, `isRunning`, `shutdown()`) to Terra's runtime while preserving all existing install semantics and adding concurrency stress coverage.

**Architecture:** Lifecycle state machine on the existing `Runtime.shared` singleton — `markRunning()` / `markUninitialized()` added to `Runtime`, provider references stored during `installOpenTelemetry()`, public `Terra.shutdown()` flushes/tears down providers and resets to `.uninitialized` so `start()` can be called again.

**Tech Stack:** Swift 5.9, opentelemetry-swift 2.3.0+, XCTest (for lifecycle isolation tests), swift-testing (for concurrency stress tests), NSLock (existing pattern).

---

## Orientation

Key files you will touch:

| File | Role |
|------|------|
| `Sources/Terra/Terra+Runtime.swift` | Add `Terra.LifecycleState`, lifecycle state to `Runtime` |
| `Sources/Terra/Terra+OpenTelemetry.swift` | Store provider refs, add `shutdown()`, call `markRunning()` |
| `Sources/Terra/Terra.swift` | Add public `lifecycleState`, `isRunning`, `shutdown()` |
| `Tests/TerraTests/TerraLifecycleTests.swift` | New: deterministic lifecycle test suite |
| `Tests/TerraTests/TerraLifecycleConcurrencyTests.swift` | New: concurrency stress tests |
| `tasks/todo.md` | Update Phase 3 checklist |

Test module: `@testable import TerraCore` in `Tests/TerraTests/`.
No `Package.swift` changes needed — new test files are auto-discovered.

Existing reset hook (DEBUG only, already used in tests):
```swift
// Terra+OpenTelemetry.swift
static func resetOpenTelemetryForTesting() {
    openTelemetryInstallLock.lock()
    defer { openTelemetryInstallLock.unlock() }
    installedOpenTelemetryConfiguration = nil  // currently clears only this
}
```

---

## Task 1: Write Failing Lifecycle State Tests

**Files:**
- Create: `Tests/TerraTests/TerraLifecycleTests.swift`

**Step 1: Create the test file**

```swift
import XCTest
@testable import TerraCore

final class TerraLifecycleTests: XCTestCase {

    override func setUp() async throws {
        // Reset OTel install state before each test.
        // After Task 6, this will also reset Runtime lifecycle state.
        Terra.resetOpenTelemetryForTesting()
    }

    override func tearDown() async throws {
        // Shut down if anything was installed during the test.
        await Terra.shutdown()
    }

    // MARK: - State Query Tests

    func testInitialState_isUninitialized() {
        XCTAssertEqual(Terra.lifecycleState, .uninitialized)
        XCTAssertFalse(Terra.isRunning)
    }

    func testAfterInstall_isRunning() throws {
        let config = minimalConfig()
        try Terra.installOpenTelemetry(config)
        XCTAssertEqual(Terra.lifecycleState, .running)
        XCTAssertTrue(Terra.isRunning)
    }

    func testAfterShutdown_isUninitialized() async throws {
        try Terra.installOpenTelemetry(minimalConfig())
        XCTAssertTrue(Terra.isRunning)

        await Terra.shutdown()

        XCTAssertEqual(Terra.lifecycleState, .uninitialized)
        XCTAssertFalse(Terra.isRunning)
    }

    func testShutdown_whenNotRunning_isIdempotent() async {
        XCTAssertFalse(Terra.isRunning)
        await Terra.shutdown()  // no-op: must not crash
        await Terra.shutdown()  // second call: must not crash
        XCTAssertFalse(Terra.isRunning)
    }

    func testShutdown_isIdempotent_afterInstall() async throws {
        try Terra.installOpenTelemetry(minimalConfig())
        await Terra.shutdown()
        await Terra.shutdown()  // second call: must not crash
        XCTAssertFalse(Terra.isRunning)
    }

    func testStartAfterShutdown_succeeds() async throws {
        let config1 = minimalConfig(port: 14001)
        let config2 = minimalConfig(port: 14002)

        try Terra.installOpenTelemetry(config1)
        XCTAssertTrue(Terra.isRunning)

        await Terra.shutdown()
        XCTAssertFalse(Terra.isRunning)

        // Must succeed — state is uninitialized after shutdown
        XCTAssertNoThrow(try Terra.installOpenTelemetry(config2))
        XCTAssertTrue(Terra.isRunning)
    }

    func testStartSameConfig_isIdempotent() throws {
        let config = minimalConfig()
        try Terra.installOpenTelemetry(config)
        // Second call with identical config: no throw, stays running
        XCTAssertNoThrow(try Terra.installOpenTelemetry(config))
        XCTAssertTrue(Terra.isRunning)
    }

    func testStartDifferentConfig_throwsAlreadyInstalled() throws {
        let config1 = minimalConfig(port: 14001)
        let config2 = minimalConfig(port: 14002)
        try Terra.installOpenTelemetry(config1)
        XCTAssertThrowsError(try Terra.installOpenTelemetry(config2)) { error in
            XCTAssertEqual(error as? Terra.InstallOpenTelemetryError, .alreadyInstalled)
        }
    }
}

// MARK: - Helpers

private func minimalConfig(port: Int = 14099) -> Terra.OpenTelemetryConfiguration {
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
```

**Step 2: Run and confirm all tests fail**

```bash
swift test --filter TerraLifecycleTests 2>&1 | tail -20
```

Expected: compile error — `Terra.lifecycleState`, `Terra.isRunning`, `Terra.shutdown()` do not exist yet.

**Step 3: Commit the test file**

```bash
git add Tests/TerraTests/TerraLifecycleTests.swift
git commit -m "test(lifecycle): add failing lifecycle state and shutdown tests"
```

---

## Task 2: Add `Terra.LifecycleState` and `Runtime` Lifecycle Tracking

**Files:**
- Modify: `Sources/Terra/Terra+Runtime.swift`

**Step 1: Read the current Runtime file**

`Sources/Terra/Terra+Runtime.swift` — note the existing `NSLock` usage pattern; use it consistently.

**Step 2: Add `Terra.LifecycleState` enum and lifecycle state to `Runtime`**

Add the public enum to the `Terra` extension at the top of `Terra+Runtime.swift`:

```swift
extension Terra {
    /// The lifecycle state of the Terra runtime.
    public enum LifecycleState: Sendable, Equatable {
        /// Terra has not been started, or has been shut down. `Terra.start()` may be called.
        case uninitialized
        /// Terra is running. Telemetry is being collected and exported.
        case running
    }
}
```

Add three members to `final class Runtime` (inside the existing class, after `let metrics = TerraMetrics()`):

```swift
// MARK: - Lifecycle

private var lifecycleStateValue: Terra.LifecycleState = .uninitialized

var lifecycleState: Terra.LifecycleState {
    lock.lock()
    defer { lock.unlock() }
    return lifecycleStateValue
}

func markRunning() {
    lock.lock()
    defer { lock.unlock() }
    lifecycleStateValue = .running
}

func markUninitialized() {
    lock.lock()
    defer { lock.unlock() }
    lifecycleStateValue = .uninitialized
    privacyValue = .default
    tracerProviderOverride = nil
    loggerProviderOverride = nil
    // metrics is cleared separately by the caller (shutdown clears providers first)
}
```

**Step 3: Verify the file compiles**

```bash
swift build --target TerraCore 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!` (no errors).

**Step 4: Commit**

```bash
git add Sources/Terra/Terra+Runtime.swift
git commit -m "feat(lifecycle): add Terra.LifecycleState enum and Runtime lifecycle state tracking"
```

---

## Task 3: Add Public `Terra.lifecycleState`, `Terra.isRunning`, and `Terra.shutdown()` Stubs

**Files:**
- Modify: `Sources/Terra/Terra+OpenTelemetry.swift`

**Step 1: Read the current OpenTelemetry file**

`Sources/Terra/Terra+OpenTelemetry.swift` — note where `installedOpenTelemetryConfiguration` is declared (private static). You will add provider ref storage near it.

**Step 2: Add public lifecycle query API and a stub `shutdown()` at the bottom of the non-DEBUG extension**

Find the end of `extension Terra { ... }` (before `#if DEBUG`), and add:

```swift
// MARK: - Lifecycle Queries

/// The current lifecycle state of the Terra runtime.
public static var lifecycleState: Terra.LifecycleState {
    Runtime.shared.lifecycleState
}

/// `true` when Terra has been started and is actively collecting telemetry.
public static var isRunning: Bool {
    lifecycleState == .running
}

// MARK: - Shutdown

/// Shuts down Terra gracefully.
///
/// Flushes any pending telemetry, tears down OTel providers, and resets the
/// runtime to `.uninitialized`. After this call, `Terra.start()` may be called
/// again with any configuration.
///
/// Safe to call from any context. Idempotent — calling it when Terra is not
/// running is a no-op.
public static func shutdown() async {
    // Full implementation in Task 5. Stub satisfies the test compile.
    openTelemetryInstallLock.lock()
    defer { openTelemetryInstallLock.unlock() }
    guard installedOpenTelemetryConfiguration != nil else { return }
    installedOpenTelemetryConfiguration = nil
    Runtime.shared.markUninitialized()
}
```

**Step 3: Build and run lifecycle tests**

```bash
swift build --target TerraCore 2>&1 | grep -E "error:|Build complete"
swift test --filter TerraLifecycleTests 2>&1 | tail -20
```

Expected: Tests compile. `testInitialState_isUninitialized` and `testShutdown_whenNotRunning_isIdempotent` should PASS. `testAfterInstall_isRunning` should FAIL (markRunning not called yet).

**Step 4: Commit the stub**

```bash
git add Sources/Terra/Terra+OpenTelemetry.swift
git commit -m "feat(lifecycle): add public lifecycleState, isRunning, and shutdown() stub"
```

---

## Task 4: Wire `markRunning()` into `installOpenTelemetry()`

**Files:**
- Modify: `Sources/Terra/Terra+OpenTelemetry.swift`

**Step 1: Find the success path in `installOpenTelemetry`**

At line ~137 in the current file, after all providers are installed and just before closing the `do` block:

```swift
// Current code (end of do block):
    if configuration.enableMetrics {
        let meterProvider = try installMetrics(configuration: configuration)
        Terra.install(.init(privacy: Runtime.shared.privacy, meterProvider: meterProvider, registerProvidersAsGlobal: false))
    }
} catch {
    installedOpenTelemetryConfiguration = nil
    throw error
}
```

**Step 2: Add `Runtime.shared.markRunning()` inside the `do` block, after all installs succeed**

```swift
    if configuration.enableMetrics {
        let meterProvider = try installMetrics(configuration: configuration)
        Terra.install(.init(privacy: Runtime.shared.privacy, meterProvider: meterProvider, registerProvidersAsGlobal: false))
    }

    // Mark runtime as running only after all providers are successfully installed.
    Runtime.shared.markRunning()
} catch {
    installedOpenTelemetryConfiguration = nil
    throw error
}
```

**Step 3: Run lifecycle tests — more should pass**

```bash
swift test --filter TerraLifecycleTests 2>&1 | tail -25
```

Expected: `testAfterInstall_isRunning`, `testStartSameConfig_isIdempotent`, `testStartDifferentConfig_throwsAlreadyInstalled` now PASS. `testAfterShutdown_isUninitialized` and `testStartAfterShutdown_succeeds` may still FAIL (stub shutdown doesn't flush providers properly yet, but state is now reset).

Actually with the current stub, `testAfterShutdown_isUninitialized` should also PASS since the stub does reset `installedOpenTelemetryConfiguration` and calls `markUninitialized()`. Run to confirm.

**Step 4: Commit**

```bash
git add Sources/Terra/Terra+OpenTelemetry.swift
git commit -m "feat(lifecycle): wire markRunning() into installOpenTelemetry success path"
```

---

## Task 5: Store Provider References and Implement Full `Terra.shutdown()`

**Files:**
- Modify: `Sources/Terra/Terra+OpenTelemetry.swift`

**Step 1: Add private static storage for installed providers**

Near `private static var installedOpenTelemetryConfiguration: OpenTelemetryConfiguration?`, add:

```swift
private static var installedTracerProvider: TracerProviderSdk?
private static var installedMeterProvider: MeterProviderSdk?
private static var installedLoggerProvider: LoggerProviderSdk?
```

**Step 2: Capture the tracer provider in `installOpenTelemetry`**

Currently `installTracing` is called and its result used locally:
```swift
let tracerProviderSdk = try installTracing(configuration: configuration)
```

After storing the config (`installedOpenTelemetryConfiguration = configuration`), add:
```swift
installedOpenTelemetryConfiguration = configuration

let tracerProviderSdk = try installTracing(configuration: configuration)
installedTracerProvider = tracerProviderSdk  // ← ADD THIS
```

**Step 3: Capture the meter provider**

Current code (inside the `do` block):
```swift
if configuration.enableMetrics {
    let meterProvider = try installMetrics(configuration: configuration)
    Terra.install(.init(privacy: Runtime.shared.privacy, meterProvider: meterProvider, registerProvidersAsGlobal: false))
}
```

Change to:
```swift
if configuration.enableMetrics {
    let meterProvider = try installMetrics(configuration: configuration)
    installedMeterProvider = meterProvider  // ← ADD THIS
    Terra.install(.init(privacy: Runtime.shared.privacy, meterProvider: meterProvider, registerProvidersAsGlobal: false))
}
```

**Step 4: Capture the logger provider**

Current code (inside the `do` block):
```swift
if configuration.enableLogs {
    _ = try installLogs(configuration: configuration)
}
```

Change to:
```swift
if configuration.enableLogs {
    installedLoggerProvider = try installLogs(configuration: configuration)  // ← capture result
}
```

**Step 5: Clear provider refs on install failure**

In the `catch` block:
```swift
} catch {
    installedOpenTelemetryConfiguration = nil
    installedTracerProvider = nil   // ← ADD
    installedMeterProvider = nil    // ← ADD
    installedLoggerProvider = nil   // ← ADD
    throw error
}
```

**Step 6: Replace the stub `shutdown()` with the full implementation**

Find the `shutdown()` stub added in Task 3 and replace it entirely:

```swift
public static func shutdown() async {
    // Step 1: Atomically claim the installed state and retrieve provider refs.
    // This ensures idempotency: the second concurrent caller sees nil config and returns.
    openTelemetryInstallLock.lock()
    guard installedOpenTelemetryConfiguration != nil else {
        openTelemetryInstallLock.unlock()
        return
    }
    let tracer = installedTracerProvider
    let meter = installedMeterProvider
    let logger = installedLoggerProvider
    installedOpenTelemetryConfiguration = nil
    installedTracerProvider = nil
    installedMeterProvider = nil
    installedLoggerProvider = nil
    // Reset Runtime state under the same lock acquisition sequence
    // (openTelemetryInstallLock → Runtime.lock is the established lock order).
    Runtime.shared.markUninitialized()
    openTelemetryInstallLock.unlock()

    // Step 2: Flush and teardown outside the lock (may involve I/O).
    _ = tracer?.forceFlush()
    tracer?.shutdown()
    meter?.shutdown()
    logger?.shutdown()
    // Clear TerraMetrics instruments that reference the now-shut-down meter.
    Runtime.shared.metrics.configure(meterProvider: nil)
}
```

**Step 7: Update `resetOpenTelemetryForTesting()` in the `#if DEBUG` block**

This keeps the DEBUG reset consistent with the lifecycle state:

```swift
static func resetOpenTelemetryForTesting() {
    openTelemetryInstallLock.lock()
    defer { openTelemetryInstallLock.unlock() }
    installedOpenTelemetryConfiguration = nil
    installedTracerProvider = nil
    installedMeterProvider = nil
    installedLoggerProvider = nil
    Runtime.shared.markUninitialized()  // ← ADD THIS
}
```

**Step 8: Build to catch compile errors**

```bash
swift build --target TerraCore 2>&1 | grep -E "error:|warning:|Build complete"
```

Possible compile issues:
- `MeterProviderSdk` may not have a `shutdown()` method visible from this module — if so, try casting to `Closeable` or just omit the meter shutdown call with a comment.
- `LoggerProviderSdk.shutdown()` similarly — check if it exists.
- If `forceFlush()` or `shutdown()` don't exist on these types, consult the OTel SDK headers and adjust to the available API (e.g., call through a protocol, or just skip the flush for providers that don't support it).

Fix any compile errors before proceeding.

**Step 9: Run all lifecycle tests**

```bash
swift test --filter TerraLifecycleTests 2>&1 | tail -25
```

Expected: All 7 tests PASS.

**Step 10: Run existing test suites to check no regressions**

```bash
swift test --filter TerraOpenTelemetryInstallConcurrencyTests 2>&1 | tail -15
swift test --filter TerraStartTests 2>&1 | tail -15
swift test --filter TerraConcurrencyPropagationTests 2>&1 | tail -15
```

Expected: All PASS.

**Step 11: Commit**

```bash
git add Sources/Terra/Terra+OpenTelemetry.swift
git commit -m "feat(lifecycle): store provider refs and implement full Terra.shutdown()"
```

---

## Task 6: Write Concurrency Stress Tests

**Files:**
- Create: `Tests/TerraTests/TerraLifecycleConcurrencyTests.swift`

**Step 1: Create the test file**

```swift
import XCTest
@testable import TerraCore

/// Concurrency stress tests for Terra lifecycle transitions.
///
/// Each test runs O(10) concurrent tasks racing over start/shutdown to verify
/// no deadlocks, no crashes, and correct final state.
final class TerraLifecycleConcurrencyTests: XCTestCase {

    override func setUp() async throws {
        Terra.resetOpenTelemetryForTesting()
    }

    override func tearDown() async throws {
        await Terra.shutdown()
    }

    // MARK: - Parallel Install (Same Config)

    func testConcurrentInstall_sameConfig_allSucceed() async throws {
        let config = minimalConfig(port: 15001)

        // 10 concurrent installs with identical config: all must succeed (idempotent).
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { try Terra.installOpenTelemetry(config) }
            }
            try await group.waitForAll()
        }

        XCTAssertTrue(Terra.isRunning)
    }

    // MARK: - Parallel Install (Different Configs)

    func testConcurrentInstall_differentConfigs_exactlyOneSucceeds() async throws {
        let results = await withTaskGroup(of: Result<Void, Error>.self) { group in
            for port in 15010..<15020 {
                let config = minimalConfig(port: port)
                group.addTask {
                    do {
                        try Terra.installOpenTelemetry(config)
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var collected: [Result<Void, Error>] = []
            for await result in group { collected.append(result) }
            return collected
        }

        let successes = results.filter { if case .success = $0 { return true }; return false }.count
        let alreadyInstalledErrors = results.compactMap { result -> Terra.InstallOpenTelemetryError? in
            if case .failure(let e) = result { return e as? Terra.InstallOpenTelemetryError }
            return nil
        }.count

        XCTAssertEqual(successes, 1, "Exactly one concurrent install should succeed")
        XCTAssertEqual(alreadyInstalledErrors, 9, "All others should throw alreadyInstalled")
        XCTAssertTrue(Terra.isRunning)
    }

    // MARK: - Parallel Shutdown

    func testConcurrentShutdown_isIdempotent() async throws {
        try Terra.installOpenTelemetry(minimalConfig(port: 15030))

        // 5 concurrent shutdowns: all must complete without crash.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { await Terra.shutdown() }
            }
        }

        XCTAssertFalse(Terra.isRunning)
    }

    // MARK: - Interleaved Start / Shutdown

    func testStartShutdownInterleaved_noDeadlock() async throws {
        // Run 3 start/shutdown cycles sequentially to verify restartability.
        for i in 0..<3 {
            let config = minimalConfig(port: 15040 + i)
            try Terra.installOpenTelemetry(config)
            XCTAssertTrue(Terra.isRunning, "Cycle \(i): should be running after install")
            await Terra.shutdown()
            XCTAssertFalse(Terra.isRunning, "Cycle \(i): should be stopped after shutdown")
        }
    }

    // MARK: - Start After Concurrent Shutdown

    func testShutdownThenConcurrentStarts_singleWinner() async throws {
        try Terra.installOpenTelemetry(minimalConfig(port: 15050))
        await Terra.shutdown()

        // After shutdown, 5 concurrent installs with different configs:
        // exactly one wins, others throw.
        let results = await withTaskGroup(of: Result<Void, Error>.self) { group in
            for port in 15051..<15056 {
                let config = minimalConfig(port: port)
                group.addTask {
                    do {
                        try Terra.installOpenTelemetry(config)
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var collected: [Result<Void, Error>] = []
            for await result in group { collected.append(result) }
            return collected
        }

        let successes = results.filter { if case .success = $0 { return true }; return false }.count
        XCTAssertEqual(successes, 1, "Exactly one post-shutdown install should win")
        XCTAssertTrue(Terra.isRunning)
    }

    // MARK: - State Consistency Under Parallel Reads

    func testConcurrentStateReads_neverCrash() async throws {
        try Terra.installOpenTelemetry(minimalConfig(port: 15060))

        // 20 concurrent reads of lifecycleState and isRunning: must not crash.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    _ = Terra.lifecycleState
                    _ = Terra.isRunning
                }
            }
        }
        // (State may be .running or .uninitialized depending on tearDown timing — just no crash.)
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
```

**Step 2: Run the concurrency tests**

```bash
swift test --filter TerraLifecycleConcurrencyTests 2>&1 | tail -30
```

Expected: All 6 tests PASS.

If `testConcurrentInstall_differentConfigs_exactlyOneSucceeds` is flaky (race condition produces 0 or 2 successes), investigate the install lock — ensure the config comparison + store is fully atomic.

**Step 3: Commit**

```bash
git add Tests/TerraTests/TerraLifecycleConcurrencyTests.swift
git commit -m "test(lifecycle): add concurrency stress tests for lifecycle transitions"
```

---

## Task 7: Full Test Suite Verification

**Step 1: Run the three verification suites from the spec**

```bash
swift test --filter TerraLifecycleConcurrencyTests 2>&1 | tail -15
swift test --filter TerraStartTests 2>&1 | tail -15
swift test --filter TerraConcurrencyPropagationTests 2>&1 | tail -15
```

Also run the new deterministic tests:
```bash
swift test --filter TerraLifecycleTests 2>&1 | tail -15
```

Expected: All PASS.

**Step 2: Run full suite**

```bash
swift test 2>&1 | tail -30
```

Expected: Zero failures. Note any new warnings.

---

## Task 8: Update Documentation and `tasks/todo.md`

**Files:**
- Modify: `README.md`
- Modify: `tasks/todo.md`

**Step 1: Add lifecycle contract section to README**

Find the "Usage" or "Getting Started" section in README.md and add after the `Terra.start()` example:

```markdown
### Lifecycle

Terra follows an explicit, deterministic lifecycle:

| State | Meaning |
|-------|---------|
| `uninitialized` | Default. Terra has not been started (or has been shut down). |
| `running` | Terra is collecting and exporting telemetry. |

```swift
// Query state
Terra.isRunning          // Bool
Terra.lifecycleState     // Terra.LifecycleState (.uninitialized / .running)

// Graceful shutdown — flushes pending telemetry, then resets to uninitialized.
// After shutdown, Terra.start() may be called again with any configuration.
await Terra.shutdown()
```

**Idempotency rules:**
- `Terra.start()` with the **same config** while running: no-op (safe to call repeatedly).
- `Terra.start()` with a **different config** while running: throws `InstallOpenTelemetryError.alreadyInstalled`.
- `Terra.shutdown()` while not running: no-op.
- After `shutdown()`, `Terra.start()` succeeds with any config.
```

**Step 2: Update `tasks/todo.md` — mark Phase 3 items complete**

Find the Phase 3 section and update:

```markdown
- [x] **Phase 3: Runtime Lifecycle Hardening**
- [x] Add explicit lifecycle APIs for advanced users (`shutdown/reconfigure` or handle-based runtime) while preserving simple global defaults.
- [x] Guarantee deterministic behavior for repeated install/start in app + tests.
- [x] Add concurrency stress tests for runtime state transitions.
- [x] Exit criteria: lifecycle semantics documented and validated under parallel tests.
```

Add a review block after the Phase 3 section:

```markdown
## Phase 3 Review (2026-03-01)

- Added `Terra.LifecycleState` enum (`.uninitialized`, `.running`) — public, `Sendable`, `Equatable`.
- Added `Terra.lifecycleState` and `Terra.isRunning` public properties — delegate to `Runtime.shared`.
- Added `Terra.shutdown()` async — atomically claims installed state, resets under lock, then flushes/tears down providers outside the lock for maximum concurrency.
- `Runtime.markRunning()` / `markUninitialized()` maintain lifecycle state alongside OTel install state.
- `resetOpenTelemetryForTesting()` (DEBUG) updated to also call `markUninitialized()` for consistent test isolation.
- Stored `installedTracerProvider`, `installedMeterProvider`, `installedLoggerProvider` to enable provider-level flush+teardown on shutdown.
- 7 new deterministic lifecycle tests in `TerraLifecycleTests`.
- 6 new concurrency stress tests in `TerraLifecycleConcurrencyTests`.
- Lifecycle contract documented in README.
- Verification: all verification commands pass; full `swift test` green.
```

**Step 3: Commit**

```bash
git add README.md tasks/todo.md
git commit -m "docs(lifecycle): add lifecycle contract to README and update Phase 3 todo"
```

---

## Phase 3 Exit Criteria Checklist

Run before declaring done:

- [ ] `swift test --filter TerraLifecycleTests` — all 7 pass
- [ ] `swift test --filter TerraLifecycleConcurrencyTests` — all 6 pass
- [ ] `swift test --filter TerraOpenTelemetryInstallConcurrencyTests` — all existing pass
- [ ] `swift test --filter TerraStartTests` — all existing pass
- [ ] `swift test --filter TerraConcurrencyPropagationTests` — all existing pass
- [ ] `swift test` — zero failures
- [ ] `Terra.lifecycleState` returns `.uninitialized` before first `start()` call
- [ ] `Terra.lifecycleState` returns `.running` after successful `start()`
- [ ] `Terra.lifecycleState` returns `.uninitialized` after `shutdown()`
- [ ] `shutdown()` → `start()` → `shutdown()` cycle works 3× without error
- [ ] README contains lifecycle contract section
- [ ] `tasks/todo.md` Phase 3 is marked complete

---

## Lifecycle Contract (Final)

```
Terra lifecycle rules:

1. Initial state: .uninitialized
2. Terra.start() / Terra.installOpenTelemetry() on .uninitialized → .running
3. Terra.start() on .running with same config → .running (idempotent, no error)
4. Terra.start() on .running with different config → throws alreadyInstalled (.running unchanged)
5. Terra.shutdown() on .running → flushes exports, shuts down providers, → .uninitialized
6. Terra.shutdown() on .uninitialized → no-op
7. After .uninitialized (via shutdown), Terra.start() may be called with any config
8. All transitions are thread-safe; concurrent callers observe consistent state
```
