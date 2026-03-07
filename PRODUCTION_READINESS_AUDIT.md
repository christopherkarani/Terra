# Terra SDK — Production Readiness Audit

**Date:** 2026-03-07
**Auditor:** Principal Engineer Review
**Scope:** Full repository audit — all source modules, tests, CI, dependencies
**Commit:** `5364e8c` (master)

---

## 1. Executive Summary

### Overall Production Readiness Score: 6.5 / 10

Terra is a well-architected observability SDK with sound foundations — proper use of
OpenTelemetry, typed span scopes, privacy-first defaults, and a clean module
decomposition. However, several categories of issues must be addressed before this
SDK should be shipped in production applications where reliability is critical.

### Top 5 Critical Risks

| # | Risk | Severity | Module |
|---|------|----------|--------|
| 1 | **Weak anonymization key fallback** — UUID-based key when `SecRandomCopyBytes` fails | Blocker | TerraCore |
| 2 | **OTLPDecoder unbounded array/kvlist breadth** — memory exhaustion DoS via crafted payloads | Major | TerraTraceKit |
| 3 | **`Runtime` is `final class` with NSLock, not an actor** — lifecycle state machine has TOCTOU gaps between individual lock acquisitions | Major | TerraCore |
| 4 | **CoreML swizzle dedup is non-atomic** — documented but creates duplicate spans under concurrency | Major | TerraCoreML |
| 5 | **No graceful degradation when OTel export fails** — silent data loss with no backpressure signal | Major | TerraCore |

### Release Blockers

1. **B-1:** Anonymization key generation falls back to `UUID().uuidString + UUID().uuidString` truncated to 32 bytes when `SecRandomCopyBytes` fails. UUIDs are not cryptographically random on all platforms; this weakens HMAC-SHA256 anonymization guarantees. (`Terra+Runtime.swift:271`)
2. **B-2:** `_LifecycleController` is an actor, but `_performStart` calls synchronous `installOpenTelemetry` which acquires `openTelemetryInstallLock` — if `installOpenTelemetry` throws after partially installing providers, the cleanup path (`markStopped()`) resets `privacyValue` to `.default` but does not unregister global OTel providers that were already registered.

---

## 2. Correctness Issues

### 2.1 Logic Bugs

**[Major] Lifecycle state machine TOCTOU gap** — `Terra+Lifecycle.swift:23`

The `_LifecycleController.start()` checks `Terra._lifecycleState == .stopped` (which reads
`Runtime.shared.lifecycleState` under one lock acquisition), then proceeds to call
`_performStart` which calls `installOpenTelemetry` which acquires a *different* lock
(`openTelemetryInstallLock`). Between these two checks, a concurrent caller could observe
inconsistent state. The actor serialization of `_LifecycleController` mitigates this for
the public API, but `_performStart` and `installOpenTelemetry` are `static` functions
callable independently from package-access code.

**[Major] Partial install cleanup is incomplete** — `Terra+OpenTelemetry.swift:172-180`

If `installOpenTelemetry` throws after successfully calling
`OpenTelemetry.registerTracerProvider()` (line 253), the catch block sets local references
to nil but **does not unregister the global tracer provider**. The OTel SDK's global
registry retains the provider. On retry, `augmentExisting` will find the half-configured
provider.

**[Minor] OTLPDecoder AnyValue depth guard off-by-one** — `OTLPDecoder.swift:300`

```swift
guard depth <= limits.maxAnyValueDepth else { ... }
```

With `maxAnyValueDepth=8`, the recursion allows depth values 0,1,...,8 (9 levels).
Should be `depth < limits.maxAnyValueDepth` for exactly 8 levels. Impact is minimal
(one extra level) but indicates spec misalignment.

**[Minor] `CancellationError` is caught but not recorded on span** — `Terra.swift:235-236`

The `withSpan` helper catches `CancellationError` separately and rethrows without
recording it. This means cancelled inference operations produce spans with no error
status. Depending on observability requirements, this may hide genuine cancellation
patterns. The OTel spec recommends recording cancellation.

### 2.2 Race Conditions

**[Major] CoreML swizzle dedup is context-based, not atomic** — `CoreMLInstrumentation.swift:108`

The dedup check `OpenTelemetry.instance.contextProvider.activeSpan == nil` is documented
as intentionally non-atomic. Two concurrent predictions on threads with no active span
will both create spans. In CoreML batch prediction scenarios, this creates N duplicate
spans.

**[Minor] `StreamingInferenceScope` lock/event ordering** — `Terra.swift:275-285`

The `recordToken()` method reads `firstTokenAt` under lock, sets the flag, unlocks, then
emits the event outside the lock. If two concurrent `recordToken()` calls race, the event
emission order is non-deterministic (acceptable for OTel events, but noted).

### 2.3 Unsafe Assumptions

**[Major] `JSONSerialization` used without options validation** — `AIRequestParser.swift`, `AIResponseParser.swift`

`JSONSerialization.jsonObject(with:)` is called without `.fragmentsAllowed`. If a response
body is a bare string or number (not an object), the `as? [String: Any]` cast returns nil
gracefully — but the guard returns nil (no error logged for non-dict JSON). This silently
drops valid JSON responses that use non-object top-level shapes.

**[Minor] Thermal state read on every span** — `Terra.swift:210`

`ProcessInfo.processInfo.thermalState` is called synchronously for every span creation.
On watchOS this can be expensive. Consider caching with a timer.

### 2.4 Silent Failure Paths

**[Major] Anonymization key Keychain failure is silent** — `Terra+Runtime.swift:254`

```swift
_ = storeAnonymizationKeyToKeychain(generated)
```

The return value is discarded. If Keychain storage fails (sandboxed app, CI, Linux),
every launch generates a new key, breaking HMAC correlations across sessions.
No warning is logged.

**[Minor] `installSignposts` silently ignores unavailability** — `Terra+OpenTelemetry.swift:267-269`

When `SignPostIntegration` is not importable, the function does nothing. This is intentional
but there is no runtime indicator that signposts were requested but unavailable.

---

## 3. Architecture & Design Gaps

### 3.1 Violations of Separation of Concerns

**[Minor] `Terra+FluentAPI.swift` is 1028 lines of repetitive builder structs**

Six nearly identical `*Call` structs (`InferenceCall`, `StreamingCall`, `EmbeddingCall`,
`AgentCall`, `ToolCall`, `SafetyCheckCall`) with identical `attribute()`, `runtime()`,
`provider()`, `execute()` methods. This is a textbook case for a generic builder or
protocol with default implementations.

**[Minor] `CoreMLInstrumentation` duplicates swizzle logic**

`swizzlePrediction()` and `swizzlePredictionWithOptions()` are 98% identical (60+ lines
each). Only the selector and parameter list differ. A shared closure factory would
eliminate this duplication.

### 3.2 Tight Coupling

**[Major] `Runtime.shared` singleton accessed throughout**

Every span creation, every privacy check, every metric recording goes through
`Runtime.shared`. This global singleton:
- Makes unit testing require careful `markStopped()`/`install()` reset ceremonies
- Prevents running two Terra configurations simultaneously (e.g., for testing)
- Creates hidden dependencies — `TerraSpanEnrichmentProcessor` reads `Runtime.shared.privacy`
  on every span start, coupling the processor to global state

**[Minor] `OTLPHTTPServer` mixes networking, HTTP parsing, and domain logic**

The server class handles TCP connections, HTTP request parsing, OTLP decoding, and
trace store ingestion in a single 554-line file. Extracting the HTTP parser and
connection manager would improve testability.

### 3.3 API Design Issues

**[Minor] `package` access level used pervasively for internal types**

Most of the Core API (`InferenceRequest`, `Privacy`, fluent builders) uses `package`
access rather than `public`. This is appropriate for the current multi-target structure
but limits the SDK's usability for external consumers who import `TerraCore` directly.
The `public` API surface (via `TerraAutoInstrument`) only exposes `Configuration` and
`start()` — the rich fluent API is invisible.

**[Minor] Deprecated closure-first factories still present**

`Terra+FluentAPI.swift` contains 12+ deprecated methods that delegate to the new builder
API. These should be removed in the next major version rather than accumulating.

---

## 4. Concurrency & Safety

### 4.1 Data Races

**[Minor] `HTTPAIInstrumentation` configuration is lock-protected but callbacks capture closures**

The `install()` method creates a `URLSessionInstrumentationConfiguration` with closures
that call `loadConfiguration()`. These closures are captured by the OTel SDK and may
execute on any thread. The `loadConfiguration()` method properly acquires the lock, so
this is safe — but the pattern means every HTTP request pays for a lock acquisition just
to check if host matching is enabled.

### 4.2 Actor Isolation

**[Correct] `_LifecycleController` actor serialization is sound**

The public API (`start`, `shutdown`, `reconfigure`) correctly flows through the actor.
The synchronous `_performStart` is called within actor context. However, the actor's
`start()` method is not `async` (it is `func start(_ config:) throws`) which means
actor reentrancy is not a concern here — but it also means the actor is used purely
for serialization, not for async operations.

**[Correct] `TraceStore` actor is well-designed**

The actor-based TraceStore properly isolates all state. The `snapshot()` caching with
`snapshotDirty` flag is correct under actor isolation.

### 4.3 Unstructured Concurrency

**[Minor] `OTLPHTTPServer.handleBody` creates unstructured `Task`** — `OTLPHTTPServer.swift:282`

The decode task is an unstructured `Task` stored in `decodeTasks[connectionID]`.
If the server is deallocated while tasks are in flight, `deinit` calls
`cleanupConnection` which cancels the task — but the `[weak self]` capture in the
task closure means the task may still be running briefly after the server is gone.
The `traceStore` reference (captured strongly by the task) keeps the store alive,
which is probably fine but not explicitly documented.

### 4.4 NSLock vs Actor

**[Observation] `Runtime` uses NSLock throughout**

`Runtime` is a `final class` with NSLock-protected properties. This is correct but
antiquated for modern Swift. An actor would provide the same guarantees with less
ceremony. The likely reason it remains a class is that OTel `SpanProcessor.onStart()`
is synchronous and cannot await actor methods. This is a valid design choice.

---

## 5. Performance Bottlenecks

### 5.1 Algorithms

**[Major] TraceStore `enforceMaxSpans` compact operation is O(n)** — `TraceStore.swift:63-66`

```swift
insertionOrder.removeFirst(insertionHead)  // O(n) array shift
```

When `insertionHead > count/2`, the entire remaining array is shifted left.
For a 10,000-span store, this is a 5,000-element memcpy on the ingestion hot path.
Consider using a `Deque` or circular buffer.

**[Minor] TraceStore `snapshot()` sorts all spans on every call** — `TraceStore.swift:44`

When `snapshotDirty`, the entire span collection is filtered, sorted, grouped, and
re-sorted. This is O(n log n) per snapshot call. For a viewer polling at 1Hz with
10,000 spans, this is significant. Consider incremental updates.

**[Minor] TerraTraceKit `TimelineViewModel` lane packing is O(n*k)** where k = number of lanes

For large traces with many concurrent spans, lane packing degrades to O(n^2) in the
worst case (n spans, each in its own lane).

### 5.2 Blocking Calls

**[Minor] `_performShutdown()` calls synchronous flush** — `Terra+OpenTelemetry.swift:389-394`

```swift
tracerProvider?.forceFlush()
meterProvider?.forceFlush()
logProcessor?.forceFlush()
```

These are synchronous I/O operations that block the calling thread. The documentation
warns about this, but since `shutdown()` is `async` (via actor), callers may not expect
the underlying synchronous blocking.

### 5.3 Excess Allocations

**[Minor] Per-span attribute dictionary creation** — `Terra.swift:27-52`

Every `withInferenceSpan` call creates a new `[String: AttributeValue]` dictionary,
populates it, then passes it to the span builder which iterates it. Consider using
the span builder's `setAttribute` directly to avoid the intermediate dictionary.

**[Minor] SHA-256 hex encoding uses `String(format:)` per byte** — `Terra+Runtime.swift:196`

```swift
digest.map { String(format: "%02x", $0) }.joined()
```

This creates 32 intermediate `String` allocations for every hash. A pre-allocated
`UnsafeMutableBufferPointer<UInt8>` with hex lookup table would be more efficient
for a hot path.

---

## 6. Security Risks

### 6.1 Cryptographic Weaknesses

**[Blocker] UUID-based anonymization key fallback** — `Terra+Runtime.swift:263-273`

```swift
static func generateAnonymizationKey() -> Data {
  #if canImport(Security)
    var bytes = [UInt8](repeating: 0, count: anonymizationKeyLengthBytes)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    if status == errSecSuccess {
      return Data(bytes)
    }
  #endif
  // FALLBACK: UUIDs are NOT cryptographically random
  let seed = UUID().uuidString + UUID().uuidString
  return Data(Data(seed.utf8).prefix(anonymizationKeyLengthBytes))
}
```

On Linux (no Security framework), this always uses the UUID fallback. UUID v4 uses
`arc4random` which is CSPRNG on most platforms, but the string encoding and truncation
reduces entropy from 256 bits to approximately 122 bits (UUID v4 has 122 random bits,
and two UUIDs concatenated as UTF-8 then truncated to 32 bytes may lose further entropy
due to the hyphen/digit structure).

**Recommendation:** Use `swift-crypto`'s `SymmetricKey(size: .bits256)` which uses the
platform's best CSPRNG, or `SystemRandomNumberGenerator` to fill the buffer.

### 6.2 Input Validation

**[Minor] Model names from CoreML are sanitized but not deeply validated** — `CoreMLInstrumentation.swift:242-250`

`sanitizeModelName` strips control characters and truncates to 256 chars. This is
reasonable, but the model name is set as a span attribute and eventually serialized
to protobuf. Extremely long model names (up to 256 chars) could inflate span size.
Consider a lower limit (64 chars).

**[Minor] `AIRequestParser` accepts 10 MiB bodies** — `AIRequestParser.swift:7`

`JSONSerialization.jsonObject(with:)` on a 10 MiB body can allocate significant memory.
This runs in the URLSession delegate callback path. A malicious/large request body
could cause memory pressure.

### 6.3 OTLPDecoder DoS Vectors

**[Major] Unbounded array/kvlist element count** — `OTLPDecoder.swift:316-322`

The depth guard limits nesting to 8 levels, but there is no breadth limit per level.
A payload with `arrayValue { values: [1, 2, ..., 1_000_000] }` at each level would
be decoded into memory without bounds checking. The `maxAttributesPerSpan` limit only
applies to top-level span attributes, not to nested array/kvlist sizes.

**Recommendation:** Add `maxArrayElements` and `maxKVListElements` to `Limits`.

**[Minor] Gzip header parsing index bounds** — `Compression.swift:110`

The FEXTRA field parsing checks `index + 2 <= bytes.count` before reading the xlen,
which is correct. However, if `bytes.count` is exactly `index + 1`, this correctly
rejects. After re-checking: the bounds checks are actually correct for the gzip
spec. Initial concern was a false positive.

### 6.4 Network Security

**[Minor] OTLPHTTPServer binds to localhost by default**

The default bind address is `127.0.0.1:4318`, which is correct for a local receiver.
However, the host is configurable and there is no warning when binding to `0.0.0.0`.
A production deployment accidentally binding to all interfaces would expose the
unauthenticated OTLP endpoint to the network.

---

## 7. Testing Review

### 7.1 Coverage Gaps

**Untested modules:**
- `TerraMetalProfiler` — no dedicated test target
- `TerraSystemProfiler` — no dedicated test target
- `TerraAccelerate` — no dedicated test target
- `OpenClawDiagnosticsExporter` — tested only via integration in `TerraAutoInstrumentTests`

**Untested code paths:**
- `Terra+OpenTelemetry.swift`: `installOpenTelemetry` error/cleanup path (partial install then throw)
- `Terra+OpenTelemetry.swift`: `augmentExisting` strategy (line 229-240)
- `Compression.swift`: gzip FEXTRA, FNAME, FCOMMENT, FHCRC flag combinations
- `OTLPHTTPServer.swift`: slow client timeout behavior, connection limit exhaustion
- `TraceStore.swift`: compact operation trigger (insertionHead > count/2)
- `Runtime.generateAnonymizationKey()`: UUID fallback path
- `Runtime.storeAnonymizationKeyToKeychain()`: update vs create paths

### 7.2 Missing Edge Cases

- No test for concurrent `Terra.start()` / `Terra.shutdown()` interleaving
- No test for `installOpenTelemetry` called with same config (idempotency)
- No test for `StreamingInferenceScope.finish()` called before any tokens recorded
- No test for OTLPDecoder with deeply nested AnyValue (depth limit verification)
- No test for `TraceStore` at exactly `maxSpans` capacity
- No fuzz testing for `AIRequestParser` or `AIResponseParser` with malformed JSON
- No test for `OTLPHTTPServer` with concurrent connections at the limit

### 7.3 Test Quality Issues

**[Minor] Tests use `swift-testing` and `XCTest` inconsistently**

The codebase mixes both frameworks. Some test files use `@Test` annotations while
others use `XCTestCase`. This creates maintenance burden and inconsistent assertion
patterns.

**[Minor] Shared mutable state in test setup**

Several tests call `Terra.install()` or `Terra.resetOpenTelemetryForTesting()` which
modifies global singleton state. Test isolation relies on explicit teardown. Parallel
test execution could produce flaky results.

### 7.4 CI Gaps

**[Minor] No iOS/watchOS/tvOS/visionOS build verification**

CI runs on `macos-latest` with `swift test` only. SPM tests do not exercise platform
conditionals (`#if canImport(CoreML)`, `#if canImport(Security)`). Platform-specific
code (Keychain, CoreML swizzling, Metal profiler) is untested in CI.

**[Minor] No memory leak detection or sanitizer runs**

No Address Sanitizer (ASan) or Thread Sanitizer (TSan) CI jobs. Given the NSLock-based
concurrency model and ObjC interop in CoreML swizzling, TSan coverage would be valuable.

---

## 8. Refactoring Opportunities

### 8.1 High-Value Refactors

**Generic Call Builder** — Replace 6 identical `*Call` structs with:
```swift
struct TelemetryCall<Request, Trace> { ... }
typealias InferenceCall = TelemetryCall<InferenceRequest, InferenceTrace>
```
This eliminates ~600 lines of duplication in `Terra+FluentAPI.swift`.

**CoreML Swizzle Factory** — Extract shared swizzle logic into a generic helper:
```swift
private static func swizzle<Args>(selector: String, wrapPrediction: @escaping (...) -> ...) { ... }
```

**Runtime as protocol** — Extract `Runtime` behind a `TerraRuntimeProvider` protocol
to enable test doubles without global state mutation.

### 8.2 Naming Improvements

- `_LifecycleController` — Remove underscore prefix; it's a proper internal type
- `_ResolvedStartConfiguration` — Same; use `ResolvedConfiguration`
- `_performStart` / `_performShutdown` — Use `performStart` / `performShutdown`
- `_lifecycleState` / `_isRunning` — These are `package` access; the underscores suggest
  they're meant to be private but are used across module boundaries
- `privacyValue` in `Runtime` — Just `privacy` (the property is already lock-protected)
- `OTLPDecompressor` — Consider `OTLPPayloadDecompressor` for clarity

### 8.3 Dead / Unused Code

- **`ProxyConfiguration`** — Referenced in `_ResolvedStartConfiguration.proxy` but never
  populated (always nil). The `.proxy` instrumentation is deprecated. Remove the field.
- **`lowRuntimeImpact`** persistence preset is just an alias for `balanced` (`Terra+Start.swift:171`).
  Either differentiate it or remove it.
- **`_RuntimeTarget.session` case** — The `Session` actor and session-based routing exists
  but the public API only exposes `start()`/`shutdown()`. The session concept appears
  to be scaffolding for a future multi-session feature.
- **`TerraTraceKit/TraceKitPlaceholder.swift`** — Placeholder file; should be removed if
  no longer needed.

---

## 9. Dependency Risk Assessment

| Dependency | Version | Risk |
|-----------|---------|------|
| opentelemetry-swift-core 2.3.0+ | Low | Stable, widely used |
| opentelemetry-swift 2.3.0+ | Low | Stable, widely used |
| swift-protobuf 1.25.0+ | Low | Stable Apple package |
| swift-crypto 4.2.0+ | Low | Stable Apple package |
| swift-syntax 602.0.0+ | **Medium** | Tied to Swift compiler version; macro compilation may break on toolchain updates |

**[Minor] swift-syntax version pin** — The `from: "602.0.0"` pin means this package
requires Swift 6.0.2+ toolchain. The `swift-tools-version:5.9` in `Package.swift`
creates a version mismatch — the package claims 5.9 compatibility but swift-syntax 602
requires 6.0+.

---

## 10. Summary of Recommendations by Priority

### Blockers (Must Fix Before Release)

1. Replace UUID fallback in `generateAnonymizationKey()` with `SymmetricKey` or
   `SystemRandomNumberGenerator` fill
2. Log a warning when Keychain storage fails for the anonymization key
3. Fix partial `installOpenTelemetry` cleanup to unregister global providers on failure

### Major (Should Fix Before Release)

4. Add breadth limits to OTLPDecoder array/kvlist parsing
5. Add `Deque` or circular buffer to TraceStore eviction
6. Document CoreML swizzle dedup limitation prominently in public API docs
7. Add TSan CI job for concurrency safety verification
8. Test `installOpenTelemetry` error/cleanup paths

### Minor (Fix in Next Sprint)

9. Extract generic `TelemetryCall` builder to reduce FluentAPI duplication
10. Remove `ProxyConfiguration` dead code
11. Fix AnyValue depth guard off-by-one
12. Add platform-specific CI builds (iOS, watchOS)
13. Standardize on `swift-testing` or `XCTest` (not both)
14. Cache `thermalState` reads with a timer
15. Consider recording `CancellationError` on spans per OTel spec

---

*End of audit.*
