# Terra Codebase Audit (2026-02-24)

## Scope

- Repository: `Terra` (SwiftPM package)
- Toolchain observed locally: Swift 6.2.1
- Primary surfaces reviewed:
  - Core public API: `Sources/Terra/`
  - Auto-instrumentation: `Sources/TerraAutoInstrument/`
  - HTTP AI instrumentation: `Sources/TerraHTTPInstrument/`
  - Core ML swizzling: `Sources/TerraCoreML/`
  - Trace receiver/decoder/view models: `Sources/TerraTraceKit/`
  - `@Traced` macro: `Sources/TerraTracedMacro*`
- Verification performed:
  - `swift test` (green after small test stabilization in `Tests/TerraHTTPInstrumentTests/HTTPIntegrationTests.swift`)

## Executive Summary

Terra’s architecture is clean and modular (Core vs. optional instrumentations vs. TraceKit). There are good safety defaults in a few places (no raw prompt capture unless explicitly enabled; OTLP body size limits; decompression cap).

The main production risks are in privacy-by-default enforcement and receiver robustness:

1. **Privacy bypass via exception capture**: span error recording attaches `exception.message` regardless of `contentPolicy`.
2. **Deterministic content hashing**: prompt/subject capture uses raw SHA-256, enabling correlation and dictionary attacks when capture is enabled.
3. **HTTP auto-instrumentation captures `url.full`** (via `URLSessionInstrumentation`), and `Terra.start()` enables localhost OpenClaw gateway host monitoring by default even when `OpenClawConfiguration.mode == .disabled`.
4. **OTLP HTTP receiver has no read deadlines** and runs decode work even after the client disconnects; this is a DoS vector if bound to non-loopback.

## Findings

### High Severity

#### H-1: Exception message capture ignores privacy policy

- Evidence:
  - `Sources/Terra/Terra.swift:218`
  - `Sources/Terra/Terra+Scope.swift:30`
- What happens:
  - `Terra.withSpan` calls `scope.recordError(error)` for thrown errors.
  - `Scope.recordError` adds an `exception` event and stores `exception.message` from `String(describing: error)` even when `Terra.Privacy.contentPolicy == .never`.
- Why it matters:
  - Downstream SDK errors often embed user inputs (prompt/tool args) or secrets (tokens) in their `Error` descriptions. This bypasses the intended “privacy safe by default” guarantee.
- Recommendation:
  - Gate error message recording on privacy policy:
    - Always record `exception.type`.
    - Record `exception.message` only when `contentPolicy` allows capture (or provide an installation option controlling error message capture).
    - Consider hashing/length-only strategies for error messages if you need correlation.
- Suggested tests:
  - With `Terra.install(.init(privacy: .init(contentPolicy: .never)))`, throw an error whose description includes a sentinel string and assert the exported span contains no `exception.message`.

#### H-2: Prompt/subject hashing is raw SHA-256 (correlation + dictionary attack risk)

- Evidence:
  - `Sources/Terra/Terra.swift:41` (prompt/subject captured via `redactedStringAttributes`)
  - `Sources/Terra/Terra+Runtime.swift:92` (`Runtime.sha256Hex`)
- What happens:
  - When capture is enabled, Terra emits `terra.prompt.sha256` / `terra.safety.subject.sha256` using deterministic SHA-256 of the raw string.
- Why it matters:
  - Deterministic hashes allow:
    - Cross-device/cross-install correlation of identical content.
    - Offline guessing for low-entropy strings (“reset password”, email templates, common prompts).
- Recommendation:
  - Replace raw SHA-256 with a keyed construction:
    - HMAC-SHA256 using a per-install secret (stored in Keychain when available).
    - Optionally rotate the key on a cadence to limit long-term correlation.
  - If Terra needs stable correlation, make it opt-in and explicit (e.g., `RedactionStrategy.hmacSHA256(keyID:)`), not the implied default behavior of “hashing”.
- Suggested tests:
  - Verify identical inputs produce different digests across different installation keys.
  - Verify digests change after key rotation.

#### H-3: OTLP HTTP receiver is susceptible to slow-loris and wasted decode work

- Evidence:
  - No per-connection read deadline:
    - `Sources/TerraTraceKit/OTLPHTTPServer.swift:134`
    - `Sources/TerraTraceKit/OTLPHTTPServer.swift:189`
  - Decode/ingest work runs in a `Task` unrelated to connection lifetime:
    - `Sources/TerraTraceKit/OTLPHTTPServer.swift:229`
- Why it matters:
  - A client can hold connections open and drip bytes slowly, pinning the server at `maxActiveConnections` (64).
  - A client can send a large compressed payload and disconnect; decode/decompression still runs and consumes CPU/memory.
- Recommendation:
  - Add per-connection idle/read deadlines for header/body.
  - Tie the decode task to connection lifecycle:
    - cancel work when the connection is `.failed`/`.cancelled`.
    - check `Task.isCancelled` before decompression/parsing/ingest.
  - If the server is ever allowed to bind to non-loopback, consider basic authentication and rate limiting.

### Medium Severity

#### M-1: `Terra.start()` enables localhost OpenClaw gateway monitoring by default (even when mode disabled)

- Evidence:
  - Default instrumentations include OpenClaw gateway:
    - `Sources/TerraAutoInstrument/Terra+Start.swift:71`
    - `Sources/TerraAutoInstrument/Terra+Start.swift:91`
  - Default OpenClaw configuration includes localhost hosts even when disabled:
    - `Sources/TerraAutoInstrument/OpenClawConfiguration.swift:36`
  - Host monitoring merges those hosts:
    - `Sources/TerraAutoInstrument/Terra+Start.swift:142`
- Why it matters:
  - Any app traffic to `localhost` / `127.0.0.1` can be instrumented and emit HTTP semantic convention attributes (including `url.full`) even when OpenClaw mode is disabled.
- Recommendation:
  - Make OpenClaw gateway instrumentation opt-in unless `mode` is `.gatewayOnly`/`.dualPath`, or default `gatewayHosts` to an empty set when `mode == .disabled`.
  - If keeping the current behavior, document it prominently in `README.md` under `Terra.start()` “what gets traced”.

#### M-2: HTTP AI auto-instrumentation emits full URL attributes via `URLSessionInstrumentation`

- Evidence:
  - `Sources/TerraHTTPInstrument/HTTPAIInstrumentation.swift:37` (uses `.stable` semantic convention)
- Why it matters:
  - The upstream `URLSessionInstrumentation` adds `url.full = request.url.absoluteString` for stable semantics, which includes query parameters.
  - Host allowlists reduce exposure, but localhost OpenClaw coverage increases the chance of capturing non-AI URLs.
- Recommendation:
  - If you need strict privacy: consider a Terra-owned HTTP instrumentation path that does not emit `url.full`, or contribute a toggle upstream.
  - At minimum: ensure the allowlist defaults never include localhost unless explicitly intended.

#### M-3: TraceKit decode path can do significant work within size limits

- Evidence:
  - `Sources/TerraTraceKit/OTLPDecoder.swift:130` (maps every span in the request)
- Why it matters:
  - Within a 10 MiB request you can still encode many spans/attributes and drive heavy allocations and CPU.
- Recommendation:
  - Add budgets:
    - max spans per request
    - max attributes per span
    - max depth for nested AnyValue arrays/kvlists

#### M-4: Trace file reading loads whole files with no size guard

- Evidence:
  - `Sources/TerraTraceKit/TraceFileReader.swift:22`
- Why it matters:
  - Large persistence files can cause memory spikes; on macOS the cache directory can be user-tampered.
- Recommendation:
  - Add a max file size and fail fast (or stream parse if needed).

#### M-5: Concurrency relies on `@unchecked Sendable` + upstream Span thread-safety

- Evidence:
  - `Sources/Terra/Terra+Scope.swift:12`
  - `Sources/Terra/Terra.swift:230`
  - `Sources/TerraFoundationModels/TerraTracedSession.swift:7`
- Why it matters:
  - If callers use `Task.detached` or otherwise cross concurrency domains, this can produce subtle data races or missing context propagation.
- Recommendation:
  - Document the expectation clearly (“Scope methods are safe to call concurrently *only* if OTel Span implementation is thread-safe”).
  - Consider providing a serialization option for streaming scopes (actor/queue wrapper) for hardening.

### Low Severity / Hygiene

#### L-1: CI nondeterminism and limited API-break checks

- Evidence:
  - `brew install swiftlint` unpinned: `.github/workflows/ci.yml:23`
  - API breaking changes is `continue-on-error` and covers only 2 products: `.github/workflows/ci.yml:34`
- Recommendation:
  - Pin SwiftLint version and make API break checks required for all public libraries (TerraCore, TerraCoreML, TerraHTTPInstrument, TerraFoundationModels, TerraMLX, TerraTracedMacro).

#### L-2: Documentation drift vs. code layout

- Evidence:
  - Root `CLAUDE.md` still describes components that aren’t present in `Sources/TerraAutoInstrument/` (proxy, HTTP proxy file, etc.).
- Recommendation:
  - Update `CLAUDE.md` to match the current module/file layout so future contributors don’t chase dead paths.

## Strengths Worth Keeping

- `OTLPRequestDecoder` has compressed + decompressed size limits:
  - `Sources/TerraTraceKit/OTLPDecoder.swift:49`
- `AIRequestParser` enforces a request body cap:
  - `Sources/TerraHTTPInstrument/AIRequestParser.swift:9`
- `TraceStore` is an actor with eviction, keeping UI tooling bounded:
  - `Sources/TerraTraceKit/TraceStore.swift:3`

