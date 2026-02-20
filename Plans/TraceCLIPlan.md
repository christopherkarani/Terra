# Terra Trace CLI Plan (Swift)

## Goal
Enable developers running an iOS app instrumented with `Terra` to view **live traces in a Mac terminal** via a Swift CLI. The CLI must be demo‑ready and form the foundation for a future macOS app viewer.

## Success Criteria (Demo‑Grade)
- **Simulator:** `otlpTracesEndpoint = http://localhost:<port>/v1/traces` and spans appear live in CLI.
- **Physical device:** `otlpTracesEndpoint = http://<mac_lan_ip>:<port>/v1/traces` with CLI bound to `0.0.0.0`.
- CLI renders:
  - live stream lines for each span end
  - per‑trace tree view (parent/child) with durations and key attributes
- No app changes beyond setting the OTLP HTTP endpoint.

---

## Architecture (Decision‑Complete)

### Data Flow
```
iOS App + Terra  --(OTLP/HTTP POST /v1/traces)-->  terra CLI (collector + viewer)
```

### Transport / Encoding (Required)
- Path: `POST /v1/traces`
- Content‑Type: `application/x-protobuf`
- Content‑Encoding: `gzip` (default), plus `deflate` and `identity`
- Accept OTEL headers; authentication optional in v1
- HTTP response:
  - Success: `200 OK` with OTLP `ExportTraceServiceResponse` protobuf body (empty response is allowed but not relied on).
  - Failure: `4xx/5xx` with `text/plain` error summary.

### Core Choice
Reuse OTLP HTTP protocol; CLI acts as a minimal OTLP HTTP receiver (not a full collector).

---

## Package / Targets (SwiftPM)
Add new targets/products:

1. **Library** `TerraTraceKit`
   - Responsibilities:
     - OTLP HTTP request decoding (gzip/deflate + protobuf)
     - Convert to internal model (`TraceID`, `SpanID`, `SpanRecord`, `Resource`, `Attributes`)
     - In‑memory store + indexes (by `traceID`, `spanID`, time)
     - Renderers (stream line + tree view)
   - Dependencies:
     - `OpenTelemetryProtocolExporterCommon` (OTLP proto types, via `opentelemetry-swift`)
     - `SwiftProtobuf` (explicit if needed; typically via `OpenTelemetryProtocolExporterCommon`)
     - `Foundation` + `Compression` (gzip/deflate)

2. **Executable** `terra`
   - Responsibilities:
     - CLI UX and commands
     - Runs OTLP receiver and prints views
   - Dependency:
     - `TerraTraceKit`
     - `swift-argument-parser` (recommended)

No changes required to Terra’s public API for v1.

---

## CLI UX (Concrete)

### `terra trace serve`
Starts OTLP HTTP receiver + live viewer.
- Flags:
  - `--host <ip>` default: `127.0.0.1`
  - `--port <p>` default: `4318`
  - `--bind-all` alias for host `0.0.0.0`
  - `--format stream|tree` default: `stream`
  - `--print-every <n>s` default: `2` (tree refresh cadence)
  - `--filter name=<prefix>` (optional)
  - `--filter trace=<traceId>` (optional)
- Behavior:
  - Print “how to configure app” instructions (sim + device).
  - For each request: decode, ingest, render.

### `terra trace print` (v1.1)
Offline render from captured data.
- Input: `--otlp-file <path>` or `--jsonl <path>`
- Output: `--format tree|json`

### `terra trace doctor`
Troubleshooting checklist:
- simulator endpoint guidance
- device endpoint guidance
- “no spans arriving” checklist

---

## Receiver Implementation

### Networking
Minimal HTTP/1.1 server via `Network.framework` (`NWListener` + `NWConnection`).
- Supports: `POST`, `Content-Length`, headers, body.
- Simplify v1 by sending `Connection: close` and closing after each request/response.
- Reject:
  - missing `Content-Length`
  - unsupported method/path
  - oversized body (cap e.g. 10MB)
  - oversized decompressed payload (cap e.g. 50MB) to prevent zip-bombs
- Explicit non-goal (v1): `Transfer-Encoding: chunked`. If encountered, return `411 Length Required`.
- Explicit non-goal (v1): `Expect: 100-continue`. If encountered, return `417 Expectation Failed` (or ignore and treat as normal POST if trivially supported).

### Decoding Pipeline
1. Read headers + body bytes.
2. Decompress per `Content-Encoding` (gzip/deflate/identity) using `Compression` streams:
   - gzip: parse RFC1952 wrapper (header/trailer) and inflate deflate payload
   - deflate: inflate RFC1951 payload (no wrapper) via `COMPRESSION_ZLIB`
   - Always enforce a maximum *decompressed* byte count.
3. Parse protobuf:
   - `Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest(serializedData:)`
4. Convert to internal `SpanRecord`:
   - IDs, name, timestamps/duration
   - selected attributes (always include `service.name`, `span.kind`, `status.code`, `gen_ai.*`, `terra.*`)
5. Ingest into store; update indexes.

### Rendering
**Stream line** (stable format):
- `timestamp duration name traceShort spanShort key=val...`
**Tree view**:
- Group by `traceId`, build parent/child adjacency
- Sort children by start time
- Show durations + key attributes
- Handle out-of-order parents by building tree at render time from full span set

---

## Testing (TDD)
Add new tests:
1. **Decoding**
   - Protobuf decode works for known request bytes
   - gzip/deflate/identity round‑trip (match Terra exporter defaults: gzip)
   - decompressed-size limit rejects oversized payloads
2. **Ingestion**
   - Parent/child tree correctness
   - Missing parent handled as root; parent arrival later re-parents on render
3. **Rendering**
   - Stream output deterministic
   - Tree output ordering stable
4. **End‑to‑End**
   - Start receiver on ephemeral port
   - POST OTLP request
   - Assert spans appear in store and renderer output

Fixtures:
- Build protobuf spans with fixed timestamps.
- Avoid real time in tests.

Test framework:
- v1: use **XCTest** (matches current Terra test suite; minimal adoption risk).
- vNext: optionally add Swift Testing for new targets if/when repo standardizes on it.

---

## Demo Recipe
1. Mac: `swift run terra trace serve --bind-all --port 4318 --format stream`
2. Simulator app: `otlpTracesEndpoint = http://localhost:4318/v1/traces`
3. Physical device app: `otlpTracesEndpoint = http://<mac_lan_ip>:4318/v1/traces`
4. Trigger agent action; watch spans stream live.
5. iOS note: ensure ATS allows `http://` to the Mac and Local Network permissions are granted.

---

## Non‑Goals (v1)
- Full collector functionality (batching, tail sampling, metrics/logs ingest)
- GUI/TUI interactivity (stdout only)
- TLS/auth (LAN demo only)

---

## Risks & Mitigations
- **Gzip default** → implement gzip/deflate/identity decoding explicitly.
- **Simulator vs device confusion** → `trace doctor` + clear startup instructions.
- **High volume output** → filters + optional throttling.
- **Unbounded memory** → cap spans/traces (LRU or TTL) + dedupe by `(traceId, spanId)`.
- **Concurrent ingestion** → store as `actor` and render via snapshot to avoid races.
- **Non-deterministic output** → define stable ordering (sort keys, timestamps) and default retention caps for demo stability (e.g. max spans + TTL).

---

## Work Decomposition (Tier 2 Orchestration)

### Task Files (one per agent)
1. `Plans/Tasks/TraceCLI_OTLPDecode.md` — decoding + decompression + proto parse + model.
2. `Plans/Tasks/TraceCLI_Receiver.md` — HTTP server + routing + body limits.
3. `Plans/Tasks/TraceCLI_Rendering.md` — stream/tree renderers + filtering.
4. `Plans/Tasks/TraceCLI_Tests.md` — XCTest fixtures + unit/e2e (v1).
5. `Plans/Tasks/TraceCLI_CLIUX.md` — CLI commands + doctor output.

### Reviews
- Review Agent #1: concurrency/network correctness
- Review Agent #2: API/UX clarity + demo readiness

---

## Assumptions
- App already uses `Terra.installOpenTelemetry(...)` and can set `otlpTracesEndpoint`.
- We only need ended spans (SimpleSpanProcessor exports on end).
- Demo environment is trusted LAN (no auth/TLS in v1).
