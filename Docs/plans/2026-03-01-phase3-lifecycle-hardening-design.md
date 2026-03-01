# Phase 3: Runtime Lifecycle Hardening — Design Doc

**Date:** 2026-03-01
**Author:** Claude Code
**Status:** Approved

---

## Problem Statement

Terra's runtime has one-way, global installation semantics with no explicit lifecycle control. Advanced users (test harnesses, background agents, multi-step pipelines) have no way to:

- Determine whether Terra is currently running
- Shut down cleanly and restart with a different configuration
- Predictably reset state between test runs without DEBUG-only hooks

The existing `resetOpenTelemetryForTesting()` API is DEBUG-only, undocumented, and exposes a bare state-clear that skips any flush or provider teardown. The `Runtime.install()` method silently overwrites settings with no lifecycle awareness. None of this behavior is formally documented or contractually enforced.

---

## Goals

1. Explicit lifecycle state visible to callers (`Terra.isRunning`, `Terra.lifecycleState`)
2. Graceful shutdown that flushes exports and resets state so `start()` can be called again
3. Make repeated `start()` behavior fully deterministic and documented
4. Concurrency-safe lifecycle transitions (no races on parallel start/shutdown)
5. Preserve simple "just call `Terra.start()`" UX for current users
6. Enable production-grade test isolation without DEBUG-only workarounds
7. No breaking removals — additive API only

---

## Non-Goals

- Actor-based multi-tenant/scoped runtimes (future Phase N)
- Mid-flight reconfigure without shutdown (not supported; shutdown+restart is the path)
- Changing underlying OTel provider implementations at runtime (OTel SDK limitation)

---

## Approved Approach: Lifecycle State Machine on Existing Singleton

Keep `Runtime.shared` as the global singleton. Add an explicit state machine to both `Runtime` and `Terra`'s OpenTelemetry install layer. Add `Terra.shutdown()` as the canonical teardown path.

### Why not the actor-based handle approach?

The actor-based approach (Approach B) requires an internal refactor of all `Runtime.shared` callsites throughout `Terra.swift`, all span methods, metrics, and wrapper modules. That scope exceeds Phase 3 and risks regressions across the entire SDK. The state machine approach achieves identical observable guarantees with a fraction of the change surface, and can graduate to an actor-based design in a future phase.

---

## State Machine

```
                      Terra.start()
uninitialized ──────────────────────────────→ running
     ↑                                           │
     │                                           │ Terra.shutdown()
     │                                           ↓
     └───────────────────────────────────── uninitialized

State transition rules:
- start() on uninitialized  → transitions to running, installs providers
- start() on running        → idempotent (same config) or throws alreadyInstalled (different config)
- shutdown() on running     → flushes exports, tears down providers, resets to uninitialized
- shutdown() on uninitialized → no-op (idempotent)
- Concurrent start() calls  → first wins; others idempotent or throw (existing behavior preserved)
- Concurrent shutdown() calls → all succeed (idempotent; only first does work)
```

### `Terra.LifecycleState` enum

```swift
public enum LifecycleState: Sendable, Equatable {
    case uninitialized
    case running
}
```

---

## API Surface (Additive)

### On `Terra` (public, static)

```swift
// Read lifecycle state
public static var lifecycleState: Terra.LifecycleState { get }

// Convenience bool
public static var isRunning: Bool { get }

// Graceful shutdown
// Flushes pending exports, shuts down providers, resets to .uninitialized.
// After this call, Terra.start() can be called again with any configuration.
// Safe to call from any Task context. Idempotent if already uninitialized.
public static func shutdown() async
```

### On `Runtime` (internal)

```swift
enum LifecycleState { case uninitialized, running }

// Read-only atomic state
var lifecycleState: LifecycleState { get }

// Transition to running (called by install)
func markRunning()

// Transition to uninitialized (called by shutdown)
func markUninitialized()
```

---

## Data Flow

### `Terra.start()` (updated)

```
Terra.start(config)
  └→ Terra.start(config.asAutoInstrumentConfiguration())   [deprecated overload]
       └→ Terra.installOpenTelemetry(otelConfig)          [checks + installs providers]
            └→ openTelemetryInstallLock.lock()
               check installedOpenTelemetryConfiguration
                 same config → return (idempotent)
                 different   → throw alreadyInstalled
                 nil         → install, store config, Runtime.shared.markRunning()
       └→ Terra.install(Installation)                     [installs privacy/providers]
       └→ CoreML / HTTP / profiler instrumentation
```

### `Terra.shutdown()` (new)

```
Terra.shutdown()
  └→ openTelemetryInstallLock.lock()
     if installedOpenTelemetryConfiguration == nil → return (idempotent no-op)
  └→ acquire stored TracerProviderSdk reference
  └→ forceFlush() on TracerProviderSdk (await with timeout)
  └→ shutdown() on TracerProviderSdk
  └→ forceFlush() + shutdown() on MeterProviderSdk
  └→ forceFlush() + shutdown() on LoggerProviderSdk
  └→ Runtime.shared.markUninitialized()
  └→ installedOpenTelemetryConfiguration = nil
  └→ lock.unlock()
```

---

## Error Handling

| Scenario | Behavior |
|---------|---------|
| `start()` called when running with same config | Idempotent no-op, no error |
| `start()` called when running with different config | Throws `InstallOpenTelemetryError.alreadyInstalled` |
| `start()` called after `shutdown()` | Succeeds (state is uninitialized again) |
| `shutdown()` called when not running | Idempotent no-op |
| `shutdown()` called concurrently | First call does work, others see cleared state and return early |
| `forceFlush()` timeout during shutdown | Log warning, continue with teardown |

---

## Provider Teardown Strategy

The OTel SDK's `TracerProviderSdk` exposes `shutdown()`. The strategy:

1. Store a reference to the installed `TracerProviderSdk` (currently returned from `installTracing` but not stored)
2. On `shutdown()`, call `forceFlush()` then `shutdown()` on each installed provider
3. Clear all stored references in `Runtime` and the static install state

We store the provider references in new properties on the `Terra` extension (alongside `installedOpenTelemetryConfiguration`):

```swift
private static var installedTracerProvider: TracerProviderSdk?
private static var installedMeterProvider: MeterProviderSdk?
private static var installedLoggerProvider: LoggerProviderSdk?
```

---

## Testing Strategy

### TDD Order

1. Write failing tests first for the new lifecycle behaviors
2. Implement API surface to make tests pass
3. Add concurrency stress tests

### Test Cases

**Lifecycle state tests (new file: `TerraLifecycleTests.swift`)**
- `testInitialState_isUninitialized()`
- `testAfterStart_isRunning()`
- `testAfterShutdown_isUninitialized()`
- `testShutdown_isIdempotent()` — shutdown twice = no error
- `testStartAfterShutdown_succeeds()` — start → shutdown → start with new config
- `testStartSameConfig_isIdempotent()` — start → start with same config
- `testStartDifferentConfig_throwsAlreadyInstalled()` — existing behavior preserved

**Concurrency stress tests (new file: `TerraLifecycleConcurrencyTests.swift`)**
- `testParallelStart_onlyOneSucceeds_restAreIdempotent()` — TaskGroup with 10 concurrent starts
- `testParallelShutdown_isIdempotent()` — TaskGroup with 5 concurrent shutdowns
- `testStartShutdownRace_noDeadlock()` — interleaved start/shutdown pairs
- `testShutdownThenConcurrentStarts_singleWinner()` — shutdown then immediate parallel starts

**Existing test preservation**
- All existing `TerraStartTests`, `TerraOpenTelemetryInstallConcurrencyTests`, `TerraConcurrencyPropagationTests` must remain green

---

## Backward Compatibility

| Existing API | Status | Notes |
|-------------|--------|-------|
| `Terra.start(_:)` | Unchanged | Same semantics, same error behavior |
| `Terra.install(_:)` | Unchanged | Still works as before |
| `Terra.installOpenTelemetry(_:)` | Unchanged externally | Internal: now also calls `markRunning()` |
| `InstallOpenTelemetryError.alreadyInstalled` | Unchanged | Same throw conditions |
| `resetOpenTelemetryForTesting()` (DEBUG) | Preserved, now also calls `markUninitialized()` | No regression for current tests |
| `lockTestingIsolation()` | Preserved | No change |

---

## Files to Create/Modify

| File | Change |
|------|--------|
| `Sources/Terra/Terra+OpenTelemetry.swift` | Add `LifecycleState`, stored provider refs, `shutdown()`, update `installOpenTelemetry` to call `markRunning()` |
| `Sources/Terra/Terra+Runtime.swift` | Add `lifecycleState`, `markRunning()`, `markUninitialized()` to `Runtime` |
| `Sources/Terra/Terra.swift` | Add `Terra.lifecycleState`, `Terra.isRunning`, `Terra.shutdown()` public API |
| `Tests/TerraTests/TerraLifecycleTests.swift` | New: deterministic lifecycle behavior tests |
| `Tests/TerraTests/TerraLifecycleConcurrencyTests.swift` | New: concurrency stress tests |
| `tasks/todo.md` | Update Phase 3 checklist |
| `README.md` | Add lifecycle contract section |

---

## Lifecycle Contract (Final, for README)

```
Terra follows an explicit lifecycle:

1. On process start, Terra is in the `uninitialized` state.
2. `Terra.start(_:)` transitions to `running`. It is idempotent for the same
   configuration; calling it again with a different configuration throws
   `InstallOpenTelemetryError.alreadyInstalled`.
3. `Terra.shutdown()` flushes all pending telemetry, shuts down providers, and
   resets to `uninitialized`. It is safe to call concurrently and is idempotent.
4. After `shutdown()`, `Terra.start(_:)` may be called again with any configuration.
5. `Terra.isRunning` / `Terra.lifecycleState` may be queried from any context.
```

---

## Acceptance Criteria

- [ ] `Terra.lifecycleState` reflects correct state after each transition
- [ ] `Terra.shutdown()` is idempotent and concurrency-safe
- [ ] After `shutdown()`, `Terra.start()` succeeds with a new config
- [ ] Existing install semantics (idempotent/throws) are unchanged
- [ ] All new lifecycle tests pass
- [ ] Concurrency stress tests pass reliably
- [ ] Full test suite green
- [ ] Lifecycle contract documented in README
